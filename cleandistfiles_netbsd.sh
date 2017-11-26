#!/bin/sh

# cleandistfiles - delete or move away obsolete distfiles
#
# TODO:
#  - find DISTDIR automagically, cd /usr/pkgsrc (make -V DISTDIR is not
#    reliable enough), maybe parse /etc/mk.conf
#  - write manpage
#  - create pkg, submit to pkgsrc-team
#
###### HARDWIRED DEFAULTS ##############################################
DO_PRINT_OBSOLETE=unset
DO_NOTHING=unset
DO_SHA_TEST=unset
DO_MOVE=unset
DIR_PKGSRC=/usr/pkgsrc
DIR_TO_MOVE=/tmp
###### HARDWIRED DEFAULTS ##############################################
#
#  Copyright (c) 2003-2006 Karsten Kruse <tecneeq(at)tecneeq.de>
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following  disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#  3. Neither the name of the author nor the names of its contributors
#     may be used to endorse or promote products derived from this
#     software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

func_usage() {
cat <<END

 $(basename $0) deletes or moves away obsolete distfiles from DISTDIR

 Options:
  -h                  => print this help
  -c                  => print current configuration
  -s                  => show obsolete files
  -m                  => move obsolete files instead of remove
  -n                  => just print what we would do
  -d                  => compare the checksums
  -p <dir>            => where pkgsrc is
  -o <dir>            => where to move obsolete files to

 See the manpage for examples.

END
}

func_defaults() {
cat <<END
move obsolete files    : -m <${DO_MOVE}>
show obsolete files    : -s <${DO_PRINT_OBSOLETE}>
just print actions     : -n <${DO_NOTHING}>
compare checksums      : -d <${DO_SHA_TEST}>
pkgsrc is in           : -p $DIR_PKGSRC
move obsolete files to : -o $DIR_TO_MOVE
END
}

# get arguments
while getopts hcsmndp:o: opt ; do
  case "$opt" in
    h)  func_usage ; exit        ;;
    c)  func_defaults ; exit     ;;
    m)  DO_MOVE=set              ;;
    s)  DO_PRINT_OBSOLETE=set    ;;
    n)  DO_NOTHING=set           ;;
    d)  DO_SHA_TEST=set          ;;
    p)  DIR_PKGSRC="$OPTARG"     ;;
    o)  DIR_TO_MOVE="$OPTARG"   ;;
    \?) func_usage >&2 ; exit 1  ;;
  esac
done
shift $(expr $OPTIND - 1)

# init some vars we use later
STAT_FILES="0"
STAT_SIZE="0"
STAT_BLOCKS="0"
STAT_WASTED="0"
FILES_RM=""
DIRNAME=""

# is DIR_PKGSRC really pkgsrc?
if [ ! -d $DIR_PKGSRC -o ! -f ${DIR_PKGSRC}/mk/bsd.pkg.mk ] ; then
  echo >&2 "$DIR_PKGSRC does not look like the pkgsrc-dir"
  exit 1
fi

# get DISTDIR
DIR_DISTFILES=$(cd $DIR_PKGSRC ; make -V DISTDIR 2>&1 | tail -n 1)
if [ ! -d $DIR_DISTFILES ] ; then
  echo >&2 "$DIR_DISTFILES does not exist"
  exit 1
fi

# does DIR_TO_MOVE exist?
if [ $DO_MOVE = set -a ! -d $DIR_TO_MOVE ] ; then
  echo >&2 "$DIR_TO_MOVE does not exist"
  exit 1
fi

# we need tempfiles
TEMP_DIR="${TMPDIR:=/tmp}/cleandistfiles_$$"

# assure tempfiles are removed at program termination or
# after we received a signal:
trap 'rm -f "$TEMP_DIR" >/dev/null 2>&1' 0
trap "exit 2" 1 2 3 13 15

mkdir $TEMP_DIR
TMP_USEFUL=${TEMP_DIR}/useful
TMP_USE_SHA=${TEMP_DIR}/use_sha
TMP_EXISTING=${TEMP_DIR}/existing
TMP_OBSOLETE=${TEMP_DIR}/obsolete
TMP_DO_CHECK=${TEMP_DIR}/do_check
TMP_CHECKED=${TEMP_DIR}/checked
TMP_CHECKSUM_FAILED=${TEMP_DIR}/checksum_failed
TMP_OBSOLETE_CHECKSUM=${TEMP_DIR}/obsolete_checksum
touch $TMP_USEFUL $TMP_USE_SHA \
  $TMP_EXISTING $TMP_OBSOLETE \
  $TMP_DO_CHECK $TMP_CHECKED \
  $TMP_CHECKSUM_FAILED $TMP_OBSOLETE_CHECKSUM

echo -n "Generating list of useful files   ... "
grep "^SHA1" ${DIR_PKGSRC}/*/*/distinfo \
  | grep -v ' (patch-[a-z][a-z]) ' \
  | awk '{print $4, $2}' \
  | sed -e 's/[()]//g' -e 's/\.\///g' \
  | sort -u -k2 \
  > $TMP_USE_SHA
  awk '{print $2}' $TMP_USE_SHA > $TMP_USEFUL
USEFUL_FOUND=$(wc -l $TMP_USEFUL | awk '{print $1}')
if [ $USEFUL_FOUND = 0 ] ; then
  echo >&2 "Not a single useful file found, that is very unlikely."
  echo >&2 "Is $DIR_PKGSRC really the directory you have pkgsrc?"
  rm -rf $TEMP_DIR
  exit 1
fi
echo "OK ($USEFUL_FOUND found)"

echo -n "Generating list of existing files ... "
cd $DIR_DISTFILES
find . -type f -print \
  | sed 's/\.\///g' \
  | grep -v "pkg-vulnerabilities" \
  | sort -u \
  > $TMP_EXISTING
EXISTING_FOUND=$(wc -l $TMP_EXISTING | awk '{print $1}')
if [ $EXISTING_FOUND = 0 ] ; then
  echo "Ops!"
  echo "Nothing in $DIR_DISTFILES found, nothing to do."
  rm -rf $TEMP_DIR
  exit
fi
echo "OK ($EXISTING_FOUND found)"

echo -n "Generating list of obsolete files ... "
diff $TMP_EXISTING $TMP_USEFUL \
  | grep "^< " \
  | sed 's/^< //' \
  > $TMP_OBSOLETE
OBSOLETE_FOUND=$(wc -l $TMP_OBSOLETE | awk '{print $1}')
echo "OK ($OBSOLETE_FOUND found)"
if [ $OBSOLETE_FOUND = 0 ] ; then
  echo "No obsolete files found, nothing to do."
  rm -rf $TEMP_DIR
  exit
fi

echo -n "Comparing checksums               ... "
if [ $DO_SHA_TEST = set ] ; then
  cat $TMP_OBSOLETE $TMP_EXISTING | sort | uniq -u > $TMP_DO_CHECK
  DO_CHECK_FOUND=$(wc -l $TMP_DO_CHECK | awk '{print $1}')
  cd $DIR_DISTFILES
  for i in $(cat $TMP_DO_CHECK) ; do
    sha1 -n $i
  done > $TMP_CHECKED
  diff $TMP_CHECKED $TMP_USE_SHA \
    | grep "^< " \
    | sed 's/^< //' \
    > $TMP_CHECKSUM_FAILED
    awk '{print $2}' $TMP_CHECKSUM_FAILED > $TMP_OBSOLETE_CHECKSUM
  SHA_FAILED_FOUND=$(wc -l $TMP_CHECKSUM_FAILED | awk '{print $1}')
  echo "OK ($SHA_FAILED_FOUND mismatches, $DO_CHECK_FOUND tested)"
else
  echo "Skipped"
fi

# get and calculate some humanreadable stats
for i in $(cat $TMP_OBSOLETE $TMP_OBSOLETE_CHECKSUM) ; do
  STAT_FILES=$(($STAT_FILES + 1))
  STAT_SIZE=$(($STAT_SIZE + $(ls -l ${DIR_DISTFILES}/$i | awk '{print $5}')))
  STAT_BLOCKS=$(($STAT_BLOCKS + $(du ${DIR_DISTFILES}/$i | awk '{print $1}')))
  FILES_RM="$FILES_RM $i"
done
if [ $STAT_SIZE -gt 1048576 ] ; then
  STAT_WASTED="$(($STAT_SIZE / 1024 / 1024)) MB ($STAT_SIZE B)"
  STAT_DISKWASTED="$(($STAT_BLOCKS * 512 / 1024 / 1024)) MB ($(($STAT_BLOCKS * 512)) B)"
elif [ $STAT_SIZE -gt 1024 ] ; then
  STAT_WASTED="$(($STAT_SIZE / 1024)) KB ($STAT_SIZE B)"
  STAT_DISKWASTED="$(($STAT_BLOCKS * 512 / 1024)) KB ($(($STAT_BLOCKS * 512)) B)"
else
  STAT_WASTED="$STAT_SIZE B"
  STAT_DISKWASTED="$(($STAT_BLOCKS * 512)) B"
fi

# output stats
echo "Number of obsolete files            = $STAT_FILES"
echo "Size of obsolete files              = $STAT_WASTED"
echo "Wasted diskspace by obsolete files  = $STAT_DISKWASTED"

# show the files we found?
if [ $DO_PRINT_OBSOLETE = set ] ; then
  if [ $DO_MOVE = set ] ; then
    echo "Files to move             = $FILES_RM"
  else
    echo "Files to delete           = $FILES_RM"
  fi
fi

# we only print actions
if [ $DO_NOTHING = set ] ; then
  echo cd $DIR_DISTFILES
  if [ $DO_MOVE = set ] ; then
    echo mv $FILES_RM $DIR_TO_MOVE
    echo "Nothing moved"
  else
    echo rm -f $FILES_RM
    echo "Nothing deleted"
  fi
fi

# here we do the real thing
if [ $DO_NOTHING = unset ] ; then
  cd $DIR_DISTFILES

  # move or remove?
  if [ $DO_MOVE = set ] ; then
    for i in $FILES_RM ; do

      # do we have to create a directory first?
      if [ $(echo $i | grep "/") ] ; then
        DIRNAME=$(echo $i | sed 's/\// /' | awk '{print $1}')
        if [ -d ${DIR_TO_MOVE}/$DIRNAME ] ; then
          mv $i ${DIR_TO_MOVE}/$i || echo >&2 "$i not moved"
        else
          mkdir ${DIR_TO_MOVE}/$DIRNAME \
            || echo >&2 "could not create ${DIR_TO_MOVE}/$DIRNAME"
          mv $i ${DIR_TO_MOVE}/$i || echo >&2 "$i not moved"
        fi
      else
        mv $i ${DIR_TO_MOVE}/$i || echo >&2 "$i not moved"
      fi

    done
  else
    for i in $FILES_RM ; do
      rm -f $i || echo >&2 "$i not deleted"
    done
  fi

  echo "Done."
fi

# clean up
rm -rf $TEMP_DIR

# eof
