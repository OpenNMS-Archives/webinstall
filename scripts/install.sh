#!/bin/sh

# debugging variables:
# $OPENNMS_CONTINUE = don't ask to continue
# $OPENNMS_LOCAL    = don't download the functions, run locally
# $INSTALL_METHOD   = rpm/tar

HOST="install.opennms.org"

. `dirname $0`/functions.sh

cat << END_INTRO

==============================================================================
OpenNMS Web Installer v0.1
==============================================================================

END_INTRO

if [ `id -u` != 0 ]; then
	echo "you must be root to run this script!"
	echo ""
	exit 1
fi

##############################################################################
# set up java path
##############################################################################

find_java
if [ $? -ne 0 ]; then
  cat << END_NO_JDK

  I was unable to locate your java executable.  Because of licensing, I cannot
  download the Java Development Kit automatically.

  Please go to http://java.sun.com/j2se/1.4/ and download the latest JDK.

  You will need to either unset JAVA_HOME if it's currently set to an older
  JDK, or set it to the location of your JDK (ie, /usr/java/j2sdk1.4.0 for
  the default RPM install of the 1.4.0 JDK).

  Once you have the JDK installed, re-run the installation and we can
  continue.

END_NO_JDK

	exit 1
fi

if [ ! -x /usr/bin/cut ]; then
	if [ -x /bin/cut ]; then
		ln -s /bin/cut /usr/bin/cut
	fi
fi

##############################################################################
# figure out what we're running on
##############################################################################

echo -e "- determining platform... \c"

find_os
case "$INSTALL_PLATFORM" in
	linux-i386-redhat-7*)
		success $INSTALL_PLATFORM
		;;
	linux-i386-redhat-8*)
		success $INSTALL_PLATFORM
		;;
	linux-i386-redhat-9*)
		success $INSTALL_PLATFORM
		;;
	linux-i386-mandrake-8)
		success $INSTALL_PLATFORM
		;;
	linux-i386-mandrake-9)
		INSTALL_METHOD="urpmi"
		success $INSTALL_PLATFORM
		;;
	darwin-Power*)
		INSTALL_PLATFORM="darwin-powerpc"
		INSTALL_METHOD="fink"
		success $INSTALL_PLATFORM
		;;
#	linux-i386-2.4)
#		warning $INSTALL_PLATFORM
#		;;
#	linux-i386-2.2)
#		warning $INSTALL_PLATFORM
#		;;
	*)
		failed $INSTALL_PLATFORM
		cat << END_UNKNOWN_PLATFORM

  I was unable to determine what platform you are running on, or OpenNMS
  does not have pre-built binaries for your platform.

  Currently we support Red Hat Linux 7, 8 and 9, plus Mandrake 8 and 9
  and Mac OSX using this installer. Support for Debian, SuSE, Solaris 
  and others can be found on the opennms.org website and in the FAQ:
  http://faq.opennms.org

  Your platform type was detected as: $INSTALL_PLATFORM

  Please e-mail install-help@opennms.org with this platform type text and any
  information you can provide on a way to uniquely determine your OS and
  processor, and, if possible, distribution, if you're on Linux.

  At the very least, please send the output of 'uname -a', if it's available,
  and we'll look into getting your platform supported by this installer.

  Thanks!

END_UNKNOWN_PLATFORM
		exit 1
		;;

esac

case "$INSTALL_PLATFORM" in
	linux-i386-redhat*)
		echo ""
		echo "*** Warning: ***"
		echo "If you are using the PostgreSQL version that comes with"
		echo "RedHat 8 (which is, in fact, recommended), you may need"
		echo "to do some additional configuration if you get errors"
		echo "about the pg_hba.conf file.  See the FAQ and release"
		echo "notes for details."
		echo ""

		TOMCAT_VERSION=`rpm -q --queryformat '%{version}' tomcat4  2>/dev/null`
		if [ "$TOMCAT_VERSION" = "4.0.3" ]; then
			echo "*** Warning: ***"
			echo "You have a tomcat version that has issues with"
			echo "upgrading to the newest official tomcat RPM"
			echo "version.  I am going to move some things out of"
			echo "the way to make sure the upgrade goes cleanly,"
			echo "but you may need to do some manual handling of"
			echo ".rpmnew or .rpmorig files in /etc/tomcat4 when"
			echo "the upgrade has completed."
			echo ""

			if [ ! -L /etc/tomcat4/conf ]; then
				mv /etc/tomcat4/conf/tomcat4.conf /etc/tomcat4/tomcat4.conf
				rmdir /etc/tomcat4/conf && ln -s /etc/tomcat4 /etc/tomcat4/conf || echo "warning: /etc/tomcat4/conf is not empty!"
			fi
			
			if [ ! -L /var/tomcat4/conf ]; then
				mkdir -p /etc/tomcat4
				mv /var/tomcat4/conf/* /etc/tomcat4/
				rmdir /var/tomcat4/conf && ln -s /etc/tomcat4 /var/tomcat4/conf || echo "warning: couldn't remove /var/tomcat4/conf directory!"
			fi
			
			if [ ! -L /var/tomcat4/work ]; then
				mkdir -p /var/cache/tomcat4/work
				rm -rf /var/tomcat4/work && ln -s /var/cache/tomcat4/work /var/tomcat4/work || echo "warning: couldn't move work to /var/cache/tomcat4/work!"
			fi

		fi

		;;
esac

##############################################################################
# get the RPM version if any
##############################################################################

if [ -z "$INSTALL_METHOD" ]; then
	get_rpm_version
	if [ $? -eq 0 ]; then
		export INSTALL_METHOD=rpm
	else
		export INSTALL_METHOD=tar
	fi
fi

echo -e "- installation method: \c"
if [ "$INSTALL_METHOD" = "rpm" ]; then
	success $INSTALL_METHOD
elif [ "$INSTALL_METHOD" = "fink" ]; then
	success $INSTALL_METHOD
elif [ "$INSTALL_METHOD" = "urpmi" ]; then
	success $INSTALL_METHOD
else
	warning $INSTALL_METHOD
fi

if [ "$INSTALL_METHOD" = "tar" ]; then
	cat << END_TAR_ERROR

At the moment, this installer only supports RPM-based distributions.

END_TAR_ERROR
	exit 1
fi

##############################################################################
# let the user know that downloading will begin
##############################################################################

cat << END_DOWNLOAD_FILES

  NOTE:

  It is now time to start checking and downloading the OpenNMS packages and
  their requirements.  This can be upwards of 40 or 50 megabytes, depending
  on what you already have installed on your system.

END_DOWNLOAD_FILES

##############################################################################
# ask if the development libraries should be installed
##############################################################################

if [ -z "$INSTALL_TYPE" ]; then
	if [ "$INSTALL_METHOD" = "rpm" ]; then
		cat << END_DEVELOPMENT_LIBS
  In addition to the normal packages that are required for running OpenNMS,
  there are a number of extra packages that can be installed (optional
  packages that are part of dependencies, documentation, etc.)

  If you do not plan on using the Tomcat servlet engine for things other than
  OpenNMS, and you don't want the extra documentation (which is also
  available from the web site), it is safe to say "No".

END_DEVELOPMENT_LIBS

		ask_question "Should I download these extra RPMs as well?" "Y"
		if [ $? -eq 0 ]; then
			INSTALL_TYPE=full
		else
			INSTALL_TYPE=runtime
		fi
	else
		INSTALL_TYPE=full
	fi
	echo ""
fi

##############################################################################
# start of downloading files
##############################################################################

INITDIR=`find_init`

##############################################################################
# Bootstrap APT
##############################################################################

if [ "$INSTALL_METHOD" = "rpm" ]; then
	echo -e "- checking for apt... \c";
	if `rpm -q apt >/dev/null 2>&1`; then
		success "found"
		FIRST_TIME_APT=0
	else
		warning "not found"
		APT_INSTALLED=0
		#for platform in $FULL_INSTALL_PLATFORM $INSTALL_PLATFORM; do
		for platform in $INSTALL_PLATFORM; do
			echo -e "- checking for apt-$platform.rpm download... \c"
			if get_file "apt-$platform.rpm" >/dev/null 2>&1; then
				success
				install_rpm "apt-$platform.rpm"
				if [ $? -eq 0 ]; then
					APT_INSTALLED=1
					break
				fi
			else
				warning "not found"
			fi
		done
		if [ "$APT_INSTALLED" -eq 0 ]; then
			echo "Unable to get APT!  Please report this to install-help@opennms.org"
			echo "or open a bug on the OpenNMS bugzilla!"
			exit 1
		fi
		FIRST_TIME_APT=1
	fi
	echo
	SOURCES_LIST="/etc/apt/sources.list"
elif [ "$INSTALL_METHOD" = "fink" ]; then
	echo -e "- checking for apt... \c"
	if [ -x /sw/bin/apt-get ]; then
		success "found"
		SOURCES_LIST="/sw/etc/apt/sources.list"
	else
		warning "not found"
		echo ""
		echo "I didn't find apt!  Either you do not have Fink installed, or"
		echo "you have it installed in a non-standard location.  In the first"
		echo "case, please download fink from http://fink.sf.net/ otherwise"
		echo "you will need to build from source the usual way."
		exit 1
	fi

	if [ `grep opennms "$SOURCES_LIST" 2>/dev/null | wc -l` -eq 0 ]; then
		echo "" >> "$SOURCES_LIST"
		echo "# OpenNMS binary distribution" >> "$SOURCES_LIST"
		echo "deb http://$HOST/apt $INSTALL_PLATFORM main" >> "$SOURCES_LIST"
	fi
fi

if [ "$INSTALL_METHOD" = "urpmi" ]; then
	# We only allow for the time being unstable to be installed
	# experimental ...

	echo -e "- adding in urpmi sources from OpenNMS Unstable... \c";
	urpmi.addmedia opennms ftp://ftp.opennms.org/pub/releases/opennms/unstable/${INSTALL_PLATFORM}/RPMS with ./hdlist.cz
	urpmi.update opennms > /dev/null 2>&1
	success "ok"

	echo -e "- installing dependencies... "
	urpmi --media opennms --auto sharutils metamail
	urpmi --media opennms --auto rrdtool librrdtool0 librrdtool0-devel
	urpmi --media opennms --auto libpgsql postgresql-server postgresql
	urpmi --media opennms --auto postgresql-devel postgresql-jdbc 
	urpmi --media opennms --auto perl-DBI perl-DBD-Pg
	urpmi --media opennms --auto --no-verify-rpm tomcat4 tomcat4-webapps 
	success "ok"

	echo -e "- installing OpenNMS... " 
	if [ "$INSTALL_TYPE" == "full" ]; then
		urpmi --media opennms --auto opennms opennms-docs opennms-webapp
	else
		urpmi --media opennms --auto opennms opennms-webapp
	fi
	success "ok"

	echo -e "- removing urpmi sources for OpenNMS... \c"
	urpmi.removemedia opennms > /dev/null 2>&1
	success "ok"

else
	if [ `grep opennms "$SOURCES_LIST" 2>/dev/null | grep -E '(stable|unstable|snapshot)' | wc -l` -eq 0 -a "$INSTALL_METHOD" = "rpm" ]; then

		cat << END_WHICH_VERSION
  It is time to set up the location that APT will install OpenNMS from.
  There are 3 different releases of the code that you can tell APT to look
  for new packages in:
  
    1. stable:   The current OpenNMS release from the "stable" tree
    2. unstable: The current OpenNMS release from the "unstable" tree
    3. snapshot: The current OpenNMS release from development snapshots
  
  The "stable" tree contains releases that have gone through at the very
  least a minimal QA process.  The "unstable" tree contains new
  functionality over the stable releases, and is known to at least build
  and run on our test network, but has not been as rigorously tested for
  bugs.  Snapshots are the latest and greatest "bleeding-edge" built
  direct from the CVS archive and have undergone no testing whatsoever.

END_WHICH_VERSION

		STABLE_TREE="stable"
		UNSTABLE_TREE="unstable"
		SNAPSHOT_TREE="snapshot"

		DEFAULT_TREE="1"

		while /bin/true; do
			ask_question "which tree would you like to install from?" $DEFAULT_TREE
			APT_TREE="$RETURN"
			if [ "$APT_TREE" = "1" ]; then
				echo "# OpenNMS latest stable release" >> /etc/apt/sources.list
				echo "rpm http://$HOST/apt $INSTALL_PLATFORM/opennms $STABLE_TREE" >> /etc/apt/sources.list
				echo "rpm-src http://$HOST/apt $INSTALL_PLATFORM/opennms $STABLE_TREE" >> /etc/apt/sources.list
				break
			elif [ "$APT_TREE" = "2" ]; then
				echo "# OpenNMS latest official release" >> /etc/apt/sources.list
				echo "rpm http://$HOST/apt $INSTALL_PLATFORM/opennms $UNSTABLE_TREE" >> /etc/apt/sources.list
				echo "rpm-src http://$HOST/apt $INSTALL_PLATFORM/opennms $UNSTABLE_TREE" >> /etc/apt/sources.list
				break
			elif [ "$APT_TREE" = "3" ]; then
				echo "# OpenNMS latest snapshot or official release" >> /etc/apt/sources.list
				echo "rpm http://$HOST/apt $INSTALL_PLATFORM/opennms $SNAPSHOT_TREE" >> /etc/apt/sources.list
				echo "rpm-src http://$HOST/apt $INSTALL_PLATFORM/opennms $SNAPSHOT_TREE" >> /etc/apt/sources.list
				break
			else
				echo "  Huh?  '$APT_TREE' wasn't one of the choices."
			fi
		done
	fi

	##############################################################################
	# Update APT cache and install
	##############################################################################

	echo
	echo "*** UPDATING APT CACHE AND INSTALLING RPMs ***"
	echo

	echo "apt-get update"
	apt-get update

	if [ "$INSTALL_TYPE" = "full" ]; then
		if [ "$INSTALL_METHOD" = "fink" ]; then
			PACKAGES="opennms"
		else
			PACKAGES="opennms opennms-webapp opennms-docs"
		fi
	else
		PACKAGES="opennms-webapp"
	fi

	if [ "$INSTALL_METHOD" != "fink" ]; then
		# First, we install tomcat so we know the ordering is right.
		echo "apt-get install tomcat4 tomcat4-webapps rrdtool"
		apt-get -y install tomcat4 tomcat4-webapps rrdtool
		if [ $? -gt 0 ]; then
			cat <<END

  ERROR!!!  APT was unable to install your packages.
  Most often this is because of a missing JDK.

  Please resolve the issues listed above, and try again.

END
		exit 1
		fi
		echo
	fi

	# Then, install the OpenNMS packages.
	echo "apt-get install $PACKAGES"
	apt-get -y install $PACKAGES
	if [ $? -gt 0 ]; then
		cat <<END

  ERROR!!!  APT was unable to install your packages.
  Most often this is because of a missing JDK.

  Please resolve the issues listed above, and try again.

END
		exit 1
	fi
	echo

	if [ "$INSTALL_METHOD" = "rpm" ]; then
		if [ "$FIRST_TIME_APT" = "1" ]; then
			echo "Rebuilding RPM database (this may take a few minutes)..."
			rpm --rebuilddb
		fi
	fi
fi

##############################################################################
# Check PostgreSQL for IP and correct number of buffers
##############################################################################

echo -e "- checking PostgreSQL configuration... \c"
if [ -z "$PGDATA" ]; then
	PGDATA="/var/lib/pgsql/data"
fi
if [ -d "$PGDATA" ]; then
	FAILURES=0
	UPDATES=0
	if [ `cat $PGDATA/postgresql.conf 2>/dev/null | sed 's/#.*$//' | grep -v '^[ 	]*$' | grep tcpip_socket | grep true | wc -l` -eq 0 ]; then
		echo "tcpip_socket = true" >> $PGDATA/postgresql.conf
		if [ $? -gt 0 ]; then
			let FAILURES="$FAILURES+1"
		else
			let UPDATES="$UPDATES+1"
		fi
	fi
	CONNECTIONS="`cat $PGDATA/postgresql.conf 2>/dev/null | sed 's/#.*$//' | grep -v '^[ 	]*$' | grep max_connections | awk -F= '{ print $2 }'`"
	if [ -z "$CONNECTIONS" ]; then
		CONNECTIONS=0
	fi
	if [ $CONNECTIONS -lt 128 ]; then
		echo "max_connections = 256" >> $PGDATA/postgresql.conf
		if [ $? -gt 0 ]; then
			let FAILURES="$FAILURES+1"
		else
			let UPDATES="$UPDATES+1"
		fi
	fi
	BUFFERS="`cat $PGDATA/postgresql.conf 2>/dev/null | sed 's/#.*$//' | grep -v '^[ 	]*$' | grep shared_buffers | awk -F= '{ print $2 }'`"
	if [ -z "$BUFFERS" ]; then
		BUFFERS=0
	fi
	if [ $BUFFERS -lt 256 ]; then
		echo "shared_buffers = 512" >> $PGDATA/postgresql.conf
		if [ $? -gt 0 ]; then
			let FAILURES="$FAILURES+1"
		else
			let UPDATES="$UPDATES+1"
		fi
	fi

	if [ "$FAILURES" -gt 0 ]; then
		failed "$FAILURES failures"
		echo "  Please see the release notes on how to check your PostgreSQL"
		echo "  configuration for the right settings."
	elif [ "$UPDATES" -gt 0 ]; then
		success "$UPDATES changes"
		if [ -x $INITDIR/postgresql ]; then
			echo "- restarting PostgreSQL"
			$INITDIR/postgresql stop
			$INITDIR/postgresql start
		elif [ -x $INITDIR/rhdb ]; then
			echo "- restarting RedHatDB (postgresql)"
			$INITDIR/rhdb stop
			$INITDIR/rhdb start
		fi
	else
		success "ok"
	fi
else
	warning "not found"
	echo "  (Set $PGDATA to the location of your PostgreSQL data directory"
	echo "  and re-run this script to automatically configure PostgreSQL"
	echo "  to work with OpenNMS.  This may not be necessary on all systems.)"
fi

##############################################################################
# All Done
##############################################################################

cat << END_RELEASE_NOTES

  Installation has completed.  Please read the release notes and quick start
  guide in the documentation for last-minute installation notes, as well as
  configuration instructions, for your platform.

  If you have any issues, feel free to post your question to the dicussion
  list at http://lists.opennms.org/mailman/listinfo/discuss -- a number of
  regular users as well as OpenNMS employees and developers frequent the list.
  Also check the FAQ at http://www.opennms.org/users/faq/ for answers to
  common questions.

  Have fun!

END_RELEASE_NOTES

if [ "$INSTALL_METHOD" = "rpm" -o "$INSTALL_METHOD" = "urpmi" ]; then
	ask_question "Do you want me to try to start everything up?" "Y"
	if [ $? -lt 1 ]; then
		[ -x $INITDIR/jbossmq ] && $INITDIR/jbossmq start
		[ -x $INITDIR/opennms ] && $INITDIR/opennms start
		[ -x $INITDIR/tomcat4 ] && $INITDIR/tomcat4 start
	fi
fi
echo ""
