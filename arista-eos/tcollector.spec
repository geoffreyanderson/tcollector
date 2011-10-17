# Put the RPM in the current directory.
%define _rpmdir .
# Don't check stuff, we know exactly what we want.
%undefine __check_files
BuildArch:      noarch
Name:           tcollector
Version:        @PACKAGE_VERSION@
Release:        @RPM_REVISION@
Distribution:   buildhash=@GIT_FULLSHA1@
License:        LGPLv3+
Summary:        Data collection framework for OpenTSDB
URL:            http://opentsdb.net/tcollector.html
Provides:       tcollector = @PACKAGE_VERSION@-@RPM_REVISION@_@GIT_SHORTSHA1@
Requires:       python(abi) = @PYTHON_VERSION@
Requires:       ProcMgr
Requires:       Launcher
# The rest of this file is generated by Makefile
