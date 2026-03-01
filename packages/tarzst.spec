# tarzst.spec
#
# Spec file for packaging the tarzst.sh script for RPM-based systems.
# This version adds a 'zstar' symlink for convenience.
# To build, use the command: rpmbuild -ba tarzst.spec

%define _version 3.1
%define _release 2

Name:       tarzst
Version:    %{_version}
Release:    %{_release}%{?dist}
Summary:    A professional utility for creating secure, verifiable, and automated tar archives.

Group:      Applications/System
License:    MIT
URL:        https://github.com/user/tarzst
Source0:    tarzst.sh

# No architecture is required as it's a shell script
BuildArch:  noarch

# Define dependencies required for the script to function
Requires:   bash >= 4.0
Requires:   tar
Requires:   zstd
Requires:   coreutils
Requires:   gnupg2
# 'pv' is an optional dependency for the progress bar, so we use Recommends.
Recommends: pv

%description
tarzst is a powerful, robust command-line wrapper script for creating
compressed, verifiable, splittable, and secure tar archives. It provides the
main command 'tarzst' and a convenient alias 'zstar'.

It integrates tar, zstd, and GPG into a seamless workflow with advanced
features including:
-   Strict error checking and cleanup
-   Automatic dependency checking for end-users
-   Password protection and GPG signing/encryption
-   File splitting for large archives
-   A self-contained, intelligent decompression script generated alongside each archive
-   Configuration file support for user-defined defaults
-   Quiet mode, file logging, and hooks for automation

%prep
# The %prep section is for preparing the source code.
%setup -q -c -T
cp %{SOURCE0} .

%build
# As this is a shell script, no build steps are necessary.

%install
# The %install section describes how to install the files into a temporary
# build root, which will become the final package structure.
# Create the target directory for the executable.
install -d -m 0755 %{buildroot}%{_bindir}

# Install the script as the main executable.
install -m 0755 tarzst.sh %{buildroot}%{_bindir}/tarzst

# Create the symlink 'zstar' that points to 'tarzst'.
# The link target is relative, making the package more robust.
ln -s tarzst %{buildroot}%{_bindir}/zstar

%files
# The %files section lists all files owned by the package.
# We must include both the main executable and the new symlink.
%{_bindir}/tarzst
%{_bindir}/zstar

%changelog
* Mon Feb 23 2026 Your Name <your.email@example.com> - 3.1-2
- Added 'zstar' symlink to the 'tarzst' binary for convenience.

* Mon Feb 23 2026 Your Name <your.email@example.com> - 3.1-1
- Initial RPM packaging for version 3.1.
