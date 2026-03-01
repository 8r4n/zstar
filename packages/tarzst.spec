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
Source1:    zstar.te
Source2:    zstar.fc
Source3:    zstar.if

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
# SELinux policy tools are optional; labeling is a no-op without them.
Recommends: policycoreutils
Recommends: selinux-policy-devel

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
cp %{SOURCE1} .
cp %{SOURCE2} .
cp %{SOURCE3} .

%build
# As this is a shell script, no build steps are necessary.
# Build the SELinux policy module if selinux-policy-devel is available.
if [ -f /usr/share/selinux/devel/Makefile ]; then
    make -f /usr/share/selinux/devel/Makefile zstar.pp
fi

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

# Install the SELinux policy module if it was built.
if [ -f zstar.pp ]; then
    install -d -m 0755 %{buildroot}%{_datadir}/selinux/packages
    install -m 0644 zstar.pp %{buildroot}%{_datadir}/selinux/packages/zstar.pp
fi

%post
# Install the SELinux policy module if available.
if [ -f %{_datadir}/selinux/packages/zstar.pp ] && command -v semodule &>/dev/null; then
    semodule -i %{_datadir}/selinux/packages/zstar.pp 2>/dev/null || true
fi

%preun
# Remove the SELinux policy module on package removal.
if [ "$1" -eq 0 ] && command -v semodule &>/dev/null; then
    semodule -r zstar 2>/dev/null || true
fi

%files
# The %files section lists all files owned by the package.
# We must include both the main executable and the new symlink.
%{_bindir}/tarzst
%{_bindir}/zstar
%{_datadir}/selinux/packages/zstar.pp

%changelog
* Mon Feb 23 2026 Your Name <your.email@example.com> - 3.1-2
- Added 'zstar' symlink to the 'tarzst' binary for convenience.

* Mon Feb 23 2026 Your Name <your.email@example.com> - 3.1-1
- Initial RPM packaging for version 3.1.
