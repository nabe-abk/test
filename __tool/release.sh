#!/bin/sh

TAR="tar jcf"
EXT="bz2"

NAME="pdf-logger"
LIBNAME="plog"

#-----------------------------------------------------------
# Release checker
#-----------------------------------------------------------
__tool/checker.pl

#-----------------------------------------------------------
# get Version
#-----------------------------------------------------------
VERSION=`head -20 lib/SakiaApp/$LIBNAME.pm | grep -E '\\\$VERSION\s*=\s*' | sed "s/[^=]*=[^\"']*\([\"']\)\([^\"']*\)\1.*/\2/"`

if [ "$VERSION" = "" -o "`echo $VERSION | grep ' '`" ]
then
	echo "Version detection failed: $VERSION"
	exit
fi

#-----------------------------------------------------------
# set variables
#-----------------------------------------------------------
RELEASE=$NAME-$VERSION

BASE="
	$NAME.cgi
	$NAME.fcgi
	$NAME.httpd.pl
	$NAME.conf.cgi.sample
	README.md
	.htaccess.sample
"
EXE="
	$NAME.exe
	${NAME}_service.exe
"
#-----------------------------------------------------------
# make release directory
#-----------------------------------------------------------
if [ ! -e $RELEASE ]
then
	mkdir $RELEASE
fi

#-----------------------------------------------------------
# copy files to release directory
#-----------------------------------------------------------
cp -Rp $CPFLAGS skel pub-dist info js lib theme $RELEASE/
cp -Rp $CPFLAGS $BASE $RELEASE/

rm -rf $RELEASE/lib/Sakia/.git
rm -f  $RELEASE/js/src

cp -p $EXE $RELEASE/

#-----------------------------------------------------------
# make other directory
#-----------------------------------------------------------
# __cache
mkdir -p $RELEASE/__cache
cp -p $CPFLAGS __cache/.htaccess  $RELEASE/__cache/

# data
mkdir -p $RELEASE/data
cp -p $CPFLAGS data/.htaccess  $RELEASE/data/

# pub
mkdir -p $RELEASE/pub
cp -p $CPFLAGS pub/.gitkeep $RELEASE/pub/

#-----------------------------------------------------------
# RELEASE files check
#-----------------------------------------------------------
# if not exist RELEASE dir, exit
if [ ! -e $RELEASE/ ]
then
	echo $RELEASE/ not exists.
	exit
fi

if [ "$1" = "test" -o  "$2" = "test" ]
then
	echo
	echo No packaging for check
	exit
fi


echo "\n---Packaging--------------------------------------------------------------------"

# Windows zip
if [ `which zip` ]; then
	echo zip -q $NAME-windows_x64.zip -r $RELEASE/
	     zip -q $NAME-windows_x64.zip -r $RELEASE/
fi
rm -f $RELEASE/*.exe

#------------------------------------------------------------------

# Release file
echo $TAR $RELEASE.tar.$EXT $RELEASE/
     $TAR $RELEASE.tar.$EXT $RELEASE/

rm -rf $RELEASE
