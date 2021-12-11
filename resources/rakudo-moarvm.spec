#
# spec file for package rakudo-moarvm
#
# Copyright (c) 2020 SUSE LLC
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via https://bugs.opensuse.org/
#

%global rakudo_rev <rakudo_rev>
%global nqp_rev <nqp_rev>
%global moar_rev <moar_rev>

Name:           rakudo-moarvm
Version:        %rakudo_rev
Release:        2.1
Summary:        Raku implementation running on MoarVM
License:        Artistic-2.0
Group:          Development/Languages/Other
URL:            http://rakudo.org/
Source0:        http://raku-ci.org/test/12345/%{version}-rakudo.tar.xz
Patch0:         rakudo-test-log.diff
BuildRequires:  fdupes
BuildRequires:  moarvm-devel = %moar_rev
BuildRequires:  nqp-moarvm = %nqp_rev
BuildRequires:  perl(YAML::Tiny)
Provides:       raku = %{version}
Requires:       nqp-moarvm = %nqp_rev
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
%ifarch s390x
BuildRequires:  libffi-devel
%endif

%description
Rakudo is an implementation of the Raku programming language specification that
runs on the MoarVM virtual machine.

%prep
%setup -q -n %{rakudo_rev}-rakudo
%patch0 -p1

%build
perl Configure.pl --prefix="%{_prefix}" --ignore-errors
make

%ifnarch armv6l armv6hl
# See armv6 issue: https://github.com/rakudo/rakudo/issues/2513
%check
rm t/08-performance/99-misc.t
RAKUDO_SKIP_TIMING_TESTS=1 make test
%endif

%install
%make_install
mkdir -p "%{buildroot}/%{_datadir}/perl6/bin"
cp tools/install-dist.p6 "%{buildroot}/%{_datadir}/perl6/bin/install-perl6-dist"
chmod +x "%{buildroot}/%{_datadir}/perl6/bin/install-perl6-dist"
sed -i -e '1s:!/usr/bin/env :!/usr/bin/:' "%{buildroot}/%{_datadir}/perl6/bin"/*
rm "%{buildroot}/%{_bindir}/raku"
rm "%{buildroot}/%{_bindir}/raku-debug"
ln -s rakudo "%{buildroot}/%{_bindir}/raku"
ln -s rakudo-debug "%{buildroot}/%{_bindir}/raku-debug"
%fdupes %{buildroot}/%{_bindir}
%fdupes %{buildroot}/%{_datadir}/perl6/runtime

%files
%defattr(-,root,root)
%doc CREDITS
%license LICENSE
%{_bindir}/*
%{_datadir}/perl6

%changelog
