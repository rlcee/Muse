#! /bin/bash
#
# script to drive the muse command to setup and build Mu2e analysis repos
#

usageMuseTarball() {
    cat <<EOF
 
    muse <global options> tarball <options> <extras>

     Make a tarball, ready to be submitted to the grid.  All locally built
     products are tarred, areas on cvmfs are linked.  The tarball defaults to 
     /mu2e/data/users/\$USER/museTarball/tmp.dir/Code.tar.bz2

    <global options>
    -v, --verbose  : add verbosity

    <options>
    -h, --help  : print usage
    -t, --tmpdir : temp build space
    -e, --exportdir : landing directory for the tarball
    -r, --release : release mode, save all code, .git, and all builds

    <extras>
        extra files or directories to include in the tarball,
        path should be relative to the Muse working directory

EOF
  return
}


# Parse arguments
PARAMS="$(getopt -o ht:e:r -l tmpdir,exportdir,release --name $(basename $0) -- "$@")"
if [ $? -ne 0 ]; then
    echo "ERROR - could not parsing tarball arguments"
    usageMuseTarball
    exit 1
fi
eval set -- "$PARAMS"

TMPDIR=/mu2e/data/users/$USER/museTarball
EXPORTDIR=/mu2e/data/users/$USER/museTarball
RELEASE=false

while true
do
    case $1 in
        -h|--help)
            usageMuseTarball
            exit 0
            ;;
        -t|--tmpdir)
	    TMPDIR="$2"
            shift 2
            ;;
        -e|--exportdir)
	    EXPORTDIR="$2"
            shift
            ;;
        -r|--release)
	    RELEASE=true
            shift
            ;;
        --)
            shift
	    EXTRAS="$@"
            break
            ;;
        *)
            usageMuseTarball
	    break
            ;;
    esac
done

cd $MUSE_WORK_DIR

# determine and make the directories
mkdir -p $TMPDIR
RC=$?
if [ $RC -ne 0 ]; then
    echo "ERROR could not mkdir $TMPDIR"
    exit 1
fi

TMPSDIR=$( mktemp --directory  --tmpdir=$TMPDIR )
TMPDN=$( basename $TMPSDIR )
EXPORTSDIR=$EXPORTDIR/$TMPDN
TBALL=$TMPSDIR/Code.tar

if [ "$TMPDIR" != "$EXPORTDIR" ]; then
mkdir -p $EXPORTSDIR
RC=$?
if [ $RC -ne 0 ]; then
    echo "ERROR could not mkdir export dir $EXPORTSDIR"
    exit 1
fi
fi

if [ $MUSE_VERBOSE -gt 0 ]; then
    echo "Temp dir TMPSDIR=$TMPSDIR"
    echo "Export dir EXPORTSDIR=$EXPORTSDIR"
    echo "Release mode: $RELEASE"
    echo "Extra files: $EXTRAS"
fi


# create an empty tarball
tar -cf $TBALL -T /dev/null
# write to this tarball and do basic excludes like tmp areas
FLAGS=" -rf $TBALL  -X $MUSE_DIR/config/tarExclude.txt "
if [ "$RELEASE" == "false" ] ; then    # for grid tarball
    # also exclude *.cc and .git
    FLAGS=" $FLAGS  -X $MUSE_DIR/config/tarExcludeGrid.txt"
    # put it in a Code subdirectory
    FLAGS=" $FLAGS  --transform=s|^|Code/|   --transform=s|^Code//cvmfs|/cvmfs|  "
fi

# tar any extra files
[ -n "$EXTRAS" ] &&  tar $FLAGS $EXTRAS

if [ "$RELEASE" == "false" ] ; then    # for grid tarball
    # create a fake setup.sh 
    if [ -f "setup.sh" ]; then
	mv setup.sh setup.sh-$(date +%s)
    fi

cat >> setup.sh <<EOF
setup muse
CODE_DIR=\$(dirname \$(readlink -f \$BASH_SOURCE))
muse setup \$CODE_DIR -q $MUSE_BUILD $MUSE_COMPILER_E $MUSE_ENVSET $MUSE_OPTS
EOF

#    echo "setup muse" > setup.sh
#    TEMP=" -q $MUSE_BUILD $MUSE_COMPILER_E $MUSE_ENVSET $MUSE_OPTS"
#    echo "muse setup Code $TEMP " >> setup.sh

    tar $FLAGS setup.sh
    rm setup.sh
fi

# now the builds
linkReg="^link/*"
cvmfsReg="^/cvmfs/*"
for REPO in $MUSE_REPOS
do
    # follow links by default
    FF=" -h "
    DD=$( readlink -f $REPO )  # expanded, true dir
    if [[ "$DD" =~ $cvmfsReg ]]; then
	# if the link is to cvmfs, then just copy in the link
	FF=""
    fi

    [ $MUSE_VERBOSE -gt 0 ] && echo tar $REPO
    tar $FLAGS $FF $REPO

    # now include the repo built parts

    if [ "$RELEASE" == "true"  ]; then
	# take all existing builds
	BUILDS=$(find build -mindepth 1 -maxdepth 1 -type d)
    else
	# take only the build that's setup
	BUILDS=$MUSE_BUILD_BASE
    fi

    for BUILD in $BUILDS
    do
	[ $MUSE_VERBOSE -gt 0 ] && echo tar $BUILD/$REPO
	DD=$( readlink -f $BUILD/$REPO )  # expanded, true dir
	if [[ "$DD" =~ $cvmfsReg ]]; then
	    # just save the link
	    tar $FLAGS $FF $BUILD/$REPO
	else  
	    for BD in lib bin gen
	    do
		if [ -d $BUILD/$REPO/$BD ]; then
		    tar $FLAGS $FF $BUILD/$REPO/$BD
		fi
	    done
	fi
    done
done

[ $MUSE_VERBOSE -gt 0 ] && echo "bzip"
bzip2 $TBALL

if [ "$TMPDIR" != "$EXPORTDIR"  ]; then
    mv ${TBALL}.bz2 $EXPORTSDIR
fi

echo Tarball: $EXPORTSDIR/Code.tar.bz2

#
# finally, give the user a warning if the tarball areas are filling up
#

SIZE=$( du -ms $TMPDIR | awk '{print $1}' )
if [ $SIZE -gt 5000 ]; then
    echo "WARNING - more than 5 GB in temp dir $TMPDIR" 
fi
if [ "$TMPDIR" != "$EXPORTDIR" ]; then
    SIZE=$( du -ms $EXPORTDIR | awk '{print $1}' )
    if [ $SIZE -gt 5000 ]; then
	echo "WARNING - more than 5 GB in export dir $EXPORTDIR" 
    fi
fi

#EXPORTDIR=/pnfs/mu2e/resilient/users/$USER/museTarball


exit 0

