#!/bin/sh

# pass/fail setup
# this bit is ripped wholesale from redhat's init scripts =)

[ -z "$COLUMNS" ] && COLUMNS=80
[ -z "$OPENNMS_DEBUG" ] && OPENNMS_DEBUG=0

LOGFILE=install.log

echo > $LOGFILE

if [ -f /etc/sysconfig/init ]; then
    . /etc/sysconfig/init
else
  SETCOLOR_SUCCESS=
  SETCOLOR_FAILURE=
  SETCOLOR_WARNING=
  SETCOLOR_NORMAL=
fi

success () {
	if [ "$BOOTUP" = "color" ]; then
		$SETCOLOR_SUCCESS
		if [ -z "$*" ]; then
			echo "ok"
		else
			echo "$*"
		fi
		$SETCOLOR_NORMAL
	else
		if [ -z "$*" ]; then
			echo "ok"
		else
			echo "$*"
		fi
	fi
	return
}

failed () {
	if [ "$BOOTUP" = "color" ]; then
		$SETCOLOR_FAILURE
		if [ -z "$*" ]; then
			echo "failed"
		else
			echo "$*"
		fi
		$SETCOLOR_NORMAL
	else
		if [ -z "$*" ]; then
			echo "failed"
		else
			echo "$*"
		fi
	fi
	return 1
}

warning () {
	if [ "$BOOTUP" = "color" ]; then
		$SETCOLOR_WARNING
		if [ -z "$*" ]; then
			echo "warning"
		else
			echo "$*"
		fi
		$SETCOLOR_NORMAL
	else
		if [ -z "$*" ]; then
			echo "warning"
		else
			echo "$*"
		fi
	fi
	return
}

# set up environment variables
POSTGRESQL_MINIMUM="7.1.3-0"
JAVA_MINIMUM="1.4.0-00"
RPM_MINIMUM="3.0.5-0"
RRDTOOL_MINIMUM="1.0.33-0"
TOMCAT_MINIMUM="4.0.1-0.onms.4"
JBOSSMQ_MINIMUM='1.0-b1.onms.12'

# generic function for asking a question

ask_question () {
	[ -z "$1" ] && echo "ask_question: you didn't give a question to ask!" && return 1
	[ -z "$2" ] && echo "ask_question: you didn't provide a default answer!" && return 1

	echo -e "- $1 \c"
	if [ "$2" = "Y" -o "$2" = "y" ]; then
		echo -e "[Y/n] \c"
		YESNO=0
		DEFAULT=0
	elif [ "$2" = "N" -o "$2" = "n" ]; then
		echo -e "[y/N] \c"
		YESNO=0
		DEFAULT=1
	else
		echo -e "[$2] \c"
		YESNO=1
	fi

	read INPUT < /dev/tty
	if [ $YESNO -eq 0 ]; then
		case $INPUT in
			Y*|y*)
				return
				;;
			N*|n*)
				return 1
				;;
			*)
				return $DEFAULT
				;;
		esac
	else
		if [ -z "$INPUT" ]; then
			export RETURN=$2
			return
		else
			export RETURN="$INPUT"
			return
		fi
	fi
}

# generic functions to check a version string

format_version () {
	[ -z "$1" ] && echo "format_version: usage: format_version 7.0.3-2" && return 1

	VERSION_STRING=`echo $1 | sed -e 's#\.##g' -e 's#-.*$##g'`
	VERSION_STRING=`echo "${VERSION_STRING}000" | sed -e 's/^\(...\).*$/\1/'`
	if echo "$1" | grep -q -- -; then
		RELEASE_STRING=`echo $1 | sed -e 's#^.*\-##g'`
	else
		RELEASE_STRING=0
	fi
	[ -z "$RELEASE_STRING" ] && RELEASE_STRING=1
	#RELEASE_STRING=`echo "00000000000000000000${RELEASE_STRING}" | sed -e 's/^.*\(..........\)$/\1/'`
	echo "${VERSION_STRING}-${RELEASE_STRING}"
}

check_version () {
	[ -z "$2" ] && return 1

	VERSION_FROM=`format_version $1`
	VERSION_TO=`format_version $2`

	if [ "$VERSION_FROM" = "$VERSION_TO" ]; then return; fi

	NEWER=`echo -e "${VERSION_FROM}\n${VERSION_TO}" | sort -r | head -1`
	if [ "$NEWER" = "$VERSION_FROM" ]; then
		return
	else
		return 1
	fi
}

# make sure the JDK version is 1.3

check_java_version () {
	[ -z "$1" ] && return 1

	JAVA_PATH="$1"
	if [ -x "$JAVA_PATH/bin/java" ]; then
		JAVA_VERSION=`$JAVA_PATH/bin/java -version 2>&1 | grep "build 1.3"`
		[ -z "$JAVA_VERSION" ] && JAVA_VERSION=`$JAVA_PATH/bin/java -version 2>&1 | grep "build 1.4"`
		JAVA_VERSION=`echo "$JAVA_VERSION" | sed -e 's#-beta##'`
		JAVA_VERSION=`echo "$JAVA_VERSION" | head -1 | sed -e 's#^.*build ##' | sed -e 's#).*$##' | tr '_' '-'`
		check_version $JAVA_VERSION $JAVA_MINIMUM
		return $?
	fi
}

# locate java home
#   on success, sets JAVA_HOME

find_java () {

	echo -e "- searching for your java path... \c"

	if [ ! -z "$JAVA_HOME" ]; then
		check_java_version "$JAVA_HOME"
		if [ $? -eq 0 ]; then
			success "$JAVA_HOME"
			return
		fi
	fi

	# look for java in the path

	JAVA_PATH=`which java 2>&1 | grep -v "no java"`
	if [ ! -z "$JAVA_PATH" ]; then
		JAVA_PATH=`echo $JAVA_PATH | sed -e 's#/bin/java##'`
		if [ $? -eq 0 ]; then
			check_java_version $JAVA_PATH
			if [ $? -eq 0 ]; then
				export JAVA_HOME="$JAVA_PATH"
				success "$JAVA_HOME"
				return
			fi
		fi
	fi

	# check for the JDK installed as RPM, but not in the path

	NO_JDK=1

	for RPM_NAME in j2sdk jdk IBMJava2-SDK; do
		if [ $NO_JDK ]; then
			JDK_FILES=`rpm -ql $RPM_NAME 2>&1 | grep 'bin/java'`
			if [ $? -eq 0 ]; then
				JAVA_PATH=`echo "$JDK_FILES" | head -1 | sed -e 's#/bin/java##'`
				export JAVA_HOME="$JAVA_PATH"
				success "$JAVA_HOME"
				return
			fi
		fi
	done

	failed
	return 1

}

find_os () {

	UNAME=`which uname 2>&1 | grep -v "no uname in"`
	if [ ! -z "$UNAME" ]; then
		# good, we have uname
		OS=`$UNAME -s | tr 'A-Z' 'a-z'`
		MACHINE=`$UNAME -m | sed -e 's/i[456]86/i386/'`
		KERNEL_VER=`$UNAME -r`

		if [ x"$OS" = x"linux" ]; then
			# strip kernel version down to major and minor
			KERNEL_VER=`echo $KERNEL_VER | sed -e 's/\.[[:digit:]]*-.*//'`

			if [ -f /etc/immunix-release ]; then
				RELEASE_NUM=`cat /etc/immunix-release | sed -e 's/^.* release //' | sed -e 's/ \(.*\)$//' | sed -e 's/\..*$//'`
				export INSTALL_PLATFORM="$OS-$MACHINE-immunix-$RELEASE_NUM"
				return
			elif [ -f /etc/mandrake-release ]; then
				# it's Mandrake  =)
				RELEASE_NUM=`cat /etc/mandrake-release | sed -e 's/^.* release //' | sed -e 's/ \(.*\)$//' | sed -e 's/\..*$//'`
				export INSTALL_PLATFORM="$OS-$MACHINE-mandrake-$RELEASE_NUM"
				return
			elif [ -f /etc/redhat-release ]; then
				# RedHat
				RELEASE_NUM=`cat /etc/redhat-release | sed -e 's/^.* release //' | sed -e 's/ \(.*\)$//'`
				RELEASE_MAJOR=`echo $RELEASE_NUM | sed -e 's/\..*$//'`
				export FULL_INSTALL_PLATFORM="$OS-$MACHINE-redhat-$RELEASE_NUM"
				export INSTALL_PLATFORM="$OS-$MACHINE-redhat-$RELEASE_MAJOR"
				return
			else
				export INSTALL_PLATFORM="$OS-$MACHINE-$KERNEL_VER"
				return
			fi
		fi

		# it's not linux
		export INSTALL_PLATFORM="$OS-$MACHINE-$KERNEL_VER"

	else
		return 1
	fi

}

get_package_version () {
	PACKNAME="$1"

	VERSION=`rpm -q --queryformat '%{VERSION}' $PACKNAME 2>&1`
	RETURN=$?
	if [ "$RETURN" = 0 ]; then
		echo $VERSION
	fi
	return $RETURN
}

get_rpm_version () {

	echo -e "- checking for RPM... \c"

	RPM=`which rpm 2>&1 | grep -v "no rpm in"`
	[ -z "$RPM" ] && RPM=`locate 'bin/rpm' | grep 'bin/rpm$' | sort | head -1`

	if [ -z "$RPM" ]; then
		for i in /bin /usr/bin /usr/local/bin; do
			if [ -x "$i/rpm" ]; then
				RPM="$i/rpm"
				break
			fi
		done
	fi

	if [ -z "$RPM" ]; then
		failed
		return 1
	fi

	RPM_VERSION=`get_package_version rpm`
	if [ -z "$RPM_VERSION" ]; then
		failed
		return 1
	else
		check_version $RPM_VERSION $RPM_MINIMUM
		if [ $? -ne 0 ]; then
			warning "warning: $RPM_VERSION"
			cat << END_RPM_WARNING

  Your RPM version is less than 3.0.5, and will not work correctly with the
  OpenNMS RPMs.  I can continue with a tar-based install, but if you wish to
  have the RPMs installed, you will have to upgrade to RPM version 3.0.5 or
  later.  Most RPM3-based distributions (RedHat 6.2, Caldera eDesktop, SuSE
  6.4, etc.) should have updates available.

  If you wish to upgrade your RPM and try again, please answer "no" to the
  following question, upgrade your RPM, and run this install again.

END_RPM_WARNING

			ask_question "Should I continue with a tar-based installation?" "n"
			if [ $? -eq 0 ]; then
				unset RPM_VERSION RPM_MAJOR_VERSION
				return 1
			else
				exit 1
			fi
		fi

		success $RPM_VERSION
		return
	fi

}

install_rpm () {
	# $1 = the package name
	[ -z "$1" ] && return 1
	FAILED=0
	RPM_COMMAND="rpm -U"

	if [ -z "$2" ]; then
		# installing only one RPM
		FILE="$1"
		SHORTNAME=`basename "$FILE"`
		echo -e "  - installing $SHORTNAME... \c"
		echo "$RPM_COMMAND $SHORTNAME" >> $LOGFILE
		if $RPM_COMMAND $SHORTNAME >>$LOGFILE 2>&1; then
			success
			return 0
		else
			failed
			return 1
		fi
	else
		for i in $*; do
			PACKAGE_FILES="$i"
			for FILE in "$i"; do
				SHORTNAME=`basename "$FILE"`
				RPM_COMMAND="$RPM_COMMAND $SHORTNAME"
			done
		done

		OUTPUT=`$RPM_COMMAND 2>&1`
		echo "$RPM_COMMAND" >> $LOGFILE
		echo "$OUTPUT" >> $LOGFILE
		if [ -n "$OUTPUT" ] && (echo "$OUTPUT" | grep -q "error:" >/dev/null 2>&1); then
			return 1
		else
			return 0
		fi
	fi
}

get_filename () {
	# $1 = the package name

	PACKAGE_LINE=`cat "${INSTALL_PLATFORM}.packages" | grep -e "^$1:"`
	if [ -z "$PACKAGE_LINE" ]; then
		exit 1
	fi

	PACKAGE_LABEL=`echo $PACKAGE_LINE | awk -F: '{ print $1 }'`
	PACKAGE_NAME=`echo $PACKAGE_LINE | awk -F: '{ print $2 }'`
	PACKAGE_VERSION=`echo $PACKAGE_LINE | awk -F: '{ print $3 }'`
	PACKAGE_FILES=`echo $PACKAGE_LINE | awk -F: '{ print $4 }'`

	echo "$PACKAGE_FILES" >> $LOGFILE
	echo "$PACKAGE_FILES"
	return
}

get_rpm_name () {
	# $1 = the package name

	PACKAGE_LINE=`cat "${INSTALL_PLATFORM}.packages" | grep -e "^$1:"`
	if [ -z "$PACKAGE_LINE" ]; then
		exit 1
	fi

	PACKAGE_LABEL=`echo $PACKAGE_LINE | awk -F: '{ print $1 }'`
	PACKAGE_NAME=`echo $PACKAGE_LINE | awk -F: '{ print $2 }'`
	PACKAGE_VERSION=`echo $PACKAGE_LINE | awk -F: '{ print $3 }'`
	PACKAGE_FILES=`echo $PACKAGE_LINE | awk -F: '{ print $4 }'`

	echo "$PACKAGE_NAME"
	return
}

get_version () {
	# $1 = the package name

	PACKAGE_LINE=`cat "${INSTALL_PLATFORM}.packages" | grep -e "^$1:"`
	if [ -z "$PACKAGE_LINE" ]; then
		exit 1
	fi

	PACKAGE_LABEL=`echo $PACKAGE_LINE | awk -F: '{ print $1 }'`
	PACKAGE_NAME=`echo $PACKAGE_LINE | awk -F: '{ print $2 }'`
	PACKAGE_VERSION=`echo $PACKAGE_LINE | awk -F: '{ print $3 }'`
	PACKAGE_FILES=`echo $PACKAGE_LINE | awk -F: '{ print $4 }'`

	echo "$PACKAGE_VERSION"
	return
}

fetch_rpm () {
	# $1 = the package name
	[ -z "$1" ] && return 1
	for FILE in `get_filename "$1"`; do
		SHORTNAME=`basename "$FILE"`
		echo -e "  - fetching $SHORTNAME... \c"
		get_file $FILE
		if [ $? -eq 0 ]; then
			success
		else
			failed
			return 1
		fi
	done
	return

}

find_exe () {
	[ -z "$1" ] && echo "get_file: you didn't specify a file to find!" && exit 1
 
	FILE=`which $1 2>&1 | grep -v "no $1 in"`
	if [ $? -ne 0 ]; then
		return 1
	fi
 
	export GET_FILE=$FILE
	return
}
 
get_file () {
	[ -z "$1" ] && echo "get_file: you didn't specify a file to get!" && exit 1
	SHORTNAME=`basename "$1"`
	rm -f "$SHORTNAME"

	if find_exe snarf; then
		echo -e "(trying snarf) \c"
		echo "$GET_FILE http://$HOST/apt/$1" >>$LOGFILE
		$GET_FILE "http://$HOST/apt/$1" >>$LOGFILE 2>&1
		[ $? ] && [ -f "$SHORTNAME" ] && return
	fi
 
	if find_exe wget; then
		echo -e "(trying wget) \c"
		echo "$GET_FILE --passive-ftp http://$HOST/apt/$1" >> $LOGFILE
		$GET_FILE --passive-ftp "http://$HOST/apt/$1" >>$LOGFILE 2>&1
		[ $? ] && [ -f "$SHORTNAME" ] && return
	fi
 
	if find_exe lwp-download; then
		echo -e "(trying lwp-download) \c"
		"$GET_FILE http://$HOST/apt/$1" >>$LOGFILE
		$GET_FILE "http://$HOST/apt/$1" >>$LOGFILE 2>&1
		[ -f $1 ] && [ -f "$SHORTNAME" ] &&return
	fi
 
	if find_exe lynx; then
		echo -e "(trying lynx) \c"
		echo "$GET_FILE -source http://$HOST/apt/$1" >>$LOGFILE
		$GET_FILE -source "http://$HOST/apt/$1" > "$SHORTNAME" 2>/dev/null
		if grep -qi "404 not found" "$1" > /dev/null 2>&1; then
			rm -f $1
		else
			return
		fi
	fi
 
	return 1
}

get_libc_version () {
	echo -e "- checking libc version... \c"
	if [ "$OS" = "linux" ]; then
		for LIBC in /usr/local/lib/libc-2.*.so /lib/libc-2.*.so /usr/lib/libc-2.*.so /usr/i386-glibc21-linux/lib/libc-2.*.so; do
			if [ -f "$LIBC" ]; then
				LIBC_VERSION=`echo $LIBC | sed -e 's#^.*/libc-##' | sed -e 's#.so$##'`
				break
			fi
		done
		if [ -z "$LIBC_VERSION" ]; then
			failed
			return 1
		else
			success $LIBC_VERSION
			return
		fi
	else
		warning "unknown"
	fi
}

get_postgresql_jdbc () {
	echo -e "- checking for PostgreSQL JDBC driver... \c"
	if [ "$1" = "rpm" ]; then
		for jar in jdbc7.0-1.2.jar jdbc7.1-1.2.jar; do
			POSTGRESQL_JDBC=`rpm -ql postgresql-jdbc 2>&1 | grep "$jar"`
			if [ ! -z "$POSTGRESQL_JDBC" ]; then
				break;
			fi
		done

		POSTGRESQL_JDBC=`rpm -ql postgresql-jdbc 2>&1 | grep "jdbc7.0-1.2.jar"`
		if [ ! -z "$POSTGRESQL_JDBC" ] && [ -f "$POSTGRESQL_JDBC" ]; then
			success $POSTGRESQL_JDBC
			return
		else
			failed "not installed"
			return 1
		fi
	else
		POSTGRESQL_JDBC=`find "$POSTGRESQL_ROOT/lib" -name "jdbc7.*-1.2.jar" 2>/dev/null`
		if [ -z "$POSTGRESQL_JDBC" ]; then
			failed "not installed"
			return 1
		else
			success $POSTGRESQL_JDBC
			return
		fi
	fi

}

get_postgresql_lib () {
	echo -e "- checking for PostgreSQL library path... \c"
	export POSTGRESQL_LIB=`find $POSTGRESQL_ROOT/lib -name libpq.so 2>/dev/null | sed -e 's#/libpq.so$##'`
	if [ -z "$POSTGRESQL_LIB" ]; then
		failed "not found"
		return 1
	else
		success $POSTGRESQL_LIB
		return
	fi
}

get_postgresql_include () {
	echo -e "- checking for PostgreSQL include path... \c"
	export POSTGRESQL_INCLUDE=`find $POSTGRESQL_ROOT/include -name postgres.h 2>/dev/null | sed -e 's#/postgres.h$##'`
	if [ -z "$POSTGRESQL_INCLUDE" ]; then
		failed "not found"
		return 1
	else
		success $POSTGRESQL_INCLUDE
		return
	fi
}

get_postgresql_devel () {
	echo -e "- checking for PostgreSQL development components... \c"
	if [ "$1" = "rpm" ]; then
		POSTGRESQL_DEVEL_VERSION=`get_package_version postgresql-devel`
		check_version $POSTGRESQL_DEVEL_VERSION $POSTGRESQL_MINIMUM
		if [ $? -eq 0 ]; then
			success $POSTGRESQL_DEVEL_VERSION
			return
		else
			if [ -z "$POSTGRESQL_DEVEL_VERSION" ]; then
				failed "not installed"
			else
				warning $POSTGRESQL_DEVEL_VERSION
			fi
			return 1
		fi
	fi
}

get_postgresql_server () {
	echo -e "- checking for PostgreSQL server components... \c"
	if [ "$1" = "rpm" ]; then
		POSTGRESQL_SERVER_VERSION=`get_package_version postgresql-server`
		check_version $POSTGRESQL_SERVER_VERSION $POSTGRESQL_MINIMUM
		if [ $? -eq 0 ]; then
			success $POSTGRESQL_SERVER_VERSION
			return
		else
			if [ -z "$POSTGRESQL_SERVER_VERSION" ]; then
				failed "not installed"
			else
				warning $POSTGRESQL_SERVER_VERSION
			fi
			return 1
		fi
	else
		PLPGSQL_FOUND=`find "$POSTGRESQL_ROOT/lib" -name plpgsql.so 2>/dev/null | wc -l`
		if [ $PLPGSQL_FOUND -gt 0 ]; then
			success
			return
		else
			failed "not installed"
			return 1
		fi
	fi
}

get_postgresql_version () {
	if [ "$1" = "rpm" ]; then
		echo -e "- checking installed PostgreSQL RPM... \c"
		export POSTGRESQL_VERSION=`get_package_version postgresql`
		check_version $POSTGRESQL_VERSION $POSTGRESQL_MINIMUM
		if [ $? -eq 0 ]; then
			success $POSTGRESQL_VERSION
			echo -e "- finding PostgreSQL root... \c"
			export POSTGRESQL_ROOT=`rpm -ql postgresql 2>&1 | grep 'bin/psql' | sed -e 's#/bin/psql$##'`
			if [ -z "$POSTGRESQL_ROOT" ]; then
				failed "not installed"
				return 1
			else
				success $POSTGRESQL_ROOT
				return
			fi
		else
			if [ -z "$POSTGRESQL_VERSION" ]; then
				failed "not installed"
			else
				warning $POSTGRESQL_VERSION
			fi
			return 1
		fi
	else
		echo -e "- checking installed PostgreSQL... \c"
		for psql in /usr/local/pgsql /usr/local/postgres /usr/local/postgresql /usr/local /opt/pgsql /opt/postgres /opt/postgresql /usr /usr; do
			if [ -x "$psql/bin/psql" ]; then
				export POSTGRESQL_ROOT="$psql"
				break
			fi
		done
		if [ -z "$POSTGRESQL_ROOT" ]; then
			failed "not installed"
			return 1
		fi

		# check the version
		export POSTGRESQL_VERSION=`$POSTGRESQL_ROOT/bin/psql --version | grep psql | sed -e 's#^.*) ##'`
		if [ -z "$POSTGRESQL_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $POSTGRESQL_VERSION $POSTGRESQL_MINIMUM
			if [ $? -eq 0 ]; then
				success "$POSTGRESQL_VERSION, $POSTGRESQL_ROOT"
				return
			else
				failed $POSTGRESQL_VERSION
				return 1
			fi
		fi
	fi
}

find_init () {
	DIRS="/etc/init.d /etc/rc.d/init.d /sbin/init.d"
	for dir in $DIRS; do
		if [ -d "$dir" ]; then
			echo "$dir"
			return
		fi
	done
}

find_postgresql_init () {
	echo -e "- finding PostgreSQL init directory... \c"
	DIRS="/etc/init.d /etc/rc.d/init.d /sbin/init.d"
	FILES="pgsql postgresql"
	for dir in $DIRS; do
		for file in $FILES; do
			if [ -x "$dir/$file" ]; then
				export PGINIT="$dir/$file"
				success "$dir/$file"
				return
			fi
		done
	done
	failed "not found"
	return 1
}

get_rrdtool_devel () {
	echo -e "- finding RRDTool development components... \c"
	if [ "$1" = "rpm" ]; then
		export RRDTOOL_INCLUDE=`rpm -ql rrdtool-devel 2>&1 | grep rrd.h | sed -e 's#/rrd\.h##'`
		export RRDTOOL_LIB=`rpm -ql rrdtool-devel 2>&1 | grep librrd.a | sed -e 's#/librrd\.a##'`
	else
		export RRDTOOL_INCLUDE=`find "$RRDTOOL_ROOT/include" -name rrd.h 2>/dev/null | sed -e 's#/rrd\.h##'`
		export RRDTOOL_LIB=`find "$RRDTOOL_ROOT/lib" -name librrd.a 2>/dev/null | sed -e 's#/librrd\.a##'`
	fi

	if [ -z "$RRDTOOL_INCLUDE" ] || [ -z "$RRDTOOL_LIB" ]; then
		failed "not installed"
		return 1
	else
		success "${RRDTOOL_LIB}, ${RRDTOOL_INCLUDE}"
		return
	fi
}

get_jbossmq_version () {
	echo -e "- finding JBossMQ... \c"
	if [ "$1" = "rpm" ]; then
		export JBOSSMQ_VERSION=`rpm -q jbossmq 2>&1 | grep -v "is not installed" | sed -e 's#^jbossmq-##'`
		if [ -z "$JBOSSMQ_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $JBOSSMQ_VERSION $JBOSSMQ_MINIMUM
			if [ $? -eq 0 ]; then
				success "$JBOSSMQ_VERSION (rpm)"
				return
			else
				if [ -z "$JBOSSMQ_VERSION" ]; then
					failed "old version ($JBOSSMQ_VERSION)"
				else
					failed "not installed"
				fi
				return 1
			fi
		fi
	fi
}

get_rrdtool_version () {
	echo -e "- finding RRDTool... \c"
	if [ "$1" = "rpm" ]; then
		export RRDTOOL_VERSION=`get_package_version rrdtool`
		if [ -z "$RRDTOOL_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $RRDTOOL_VERSION $RRDTOOL_MINIMUM
			if [ $? -eq 0 ]; then
				success "$RRDTOOL_VERSION (rpm)"
				return
			else
				if [ -z "$RRDTOOL_VERSION" ]; then
					failed "old version ($RRDTOOL_VERSION)"
				else
					failed "not installed"
				fi
				return 1
			fi
		fi
	else
		export RRDTOOL_VERSION=`rrdtool --version | head -1 | sed -e 's#^RRDtool ##' | sed -e 's# *Copyright.*$##'`
		if [ -z "$RRDTOOL_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $RRDTOOL_VERSION $RRDTOOL_MINIMUM
			if [ $? -eq 0 ]; then
				export RRDTOOL_ROOT=`which rrdtool 2>&1 | grep -v "no rrdtool in" | sed -e 's#/bin/rrdtool##'`
				if [ -z "$RRDTOOL_ROOT" ]; then
					failed "cannot locate RRDTool root"
					return 1
				else
					success $RRDTOOL_VERSION
					return
				fi
			else
				failed $RRDTOOL_VERSION
				return 1
			fi
		fi
	fi
}

get_dbi_version () {
	echo -e "- finding Perl database interface... \c"
	if [ "$1" = "rpm" ]; then
		RPM_NAME=`get_rpm_name perl-dbi`
		export DBI_VERSION=`get_package_version perl-dbi`
		if [ -z "$DBI_VERSION" ]; then
			failed "not found"
			return 1
		else
			check_version $DBI_VERSION `get_version perl-dbi`
			if [ $? -eq 0 ]; then
				success "$DBI_VERSION (rpm)"
				return
			else
				failed "old version ($DBI_VERSION)"
				return 1
			fi
		fi
	fi
}

get_dbd_version () {
	echo -e "- finding Perl PostgreSQL driver... \c"
	if [ "$1" = "rpm" ]; then
		export DBD_VERSION=`get_package_version perl-DBD-Pg`
		if [ -z "$DBD_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $DBD_VERSION `get_version perl-dbd-pg`
			if [ $? -eq 0 ]; then
				success "$DBD_VERSION (rpm)"
				return
			else
				failed "old version ($DBD_VERSION)"
				return 1
			fi
		fi
	fi
}

get_opennms_version () {
	echo -e "- finding OpenNMS... \c"
	if [ "$1" = "rpm" ]; then
		export OPENNMS_VERSION=`get_package_version opennms`
		if [ -z "$OPENNMS_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $OPENNMS_VERSION `get_version opennms`
			if [ $? -eq 0 ]; then
				success "$OPENNMS_VERSION (rpm)"
				return
			else
				failed "old version ($OPENNMS_VERSION)"
				return 1
			fi
		fi
	fi
}

get_opennms_webapp_version () {
	echo -e "- finding OpenNMS Webapp... \c"
	if [ "$1" = "rpm" ]; then
		export OPENNMS_WEBAPPS_VERSION=`get_package_version opennms-webapp`
		if [ -z "$OPENNMS_WEBAPPS_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $OPENNMS_WEBAPPS_VERSION `get_version opennms-webapp`
			if [ $? -eq 0 ]; then
				success "$OPENNMS_WEBAPPS_VERSION (rpm)"
				return
			else
				failed "old version ($OPENNMS_WEBAPPS_VERSION)"
				return 1
			fi
		fi
	fi
}

get_opennms_docs_version () {
	echo -e "- finding OpenNMS Documentation... \c"
	if [ "$1" = "rpm" ]; then
		export OPENNMS_DOCS_VERSION=`get_package_version opennms-docs`
		if [ -z "$OPENNMS_DOCS_VERSION" ]; then
			failed "not installed"
			return 1
		else
			check_version $OPENNMS_DOCS_VERSION `get_version opennms-docs`
			if [ $? -eq 0 ]; then
				success "$OPENNMS_DOCS_VERSION (rpm)"
				return
			else
				failed "old version ($OPENNMS_DOCS_VERSION)"
				return 1
			fi
		fi
	fi
}

get_tomcat_version () {
	echo -e "- finding Tomcat... \c"
	if [ "$1" = "rpm" ]; then
		export TOMCAT_VERSION=`get_package_version tomcat4`
		if [ -z "$TOMCAT_VERSION" ]; then
			failed "not found"
			return 1
		else
			check_version $TOMCAT_VERSION $TOMCAT_MINIMUM
			if [ $? -eq 0 ]; then
				success "$TOMCAT_VERSION (rpm)"
				return
			else
				failed "old version ($TOMCAT_VERSION)"
				return 1
			fi
		fi
	else
		for tomcat_loc in /var/tomcat4 /opt/tomcat4 /var/tomcat /opt/tomcat /usr/local/tomcat4 /usr/local/tomcat /var/jakarta-tomcat* /opt/jakarta-tomcat* /usr/local/jakarta-tomcat*; do
			if [ -f $tomcat_loc/RELEASE-NOTES-4.0* ]; then
				export TOMCAT_VERSION=4
				export TOMCAT_ROOT=$tomcat_loc
				warning "unknown tomcat 4"
				return
			elif [ -f $tomcat_loc/bin/catalina.sh ]; then
				export TOMCAT_VERSION=4
				export TOMCAT_ROOT=$tomcat_loc
				warning "unknown tomcat 4"
				return
			elif [ -f $tomcat_loc/server/catalina.jar ]; then
				export TOMCAT_VERSION=4
				export TOMCAT_ROOT=$tomcat_loc
				warning "unknown tomcat 4"
				return
			fi
		done
		failed "not installed"
		return 1
	fi
}

