#
# spec file for package nqp-moarvm
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

%global nqp_rev 2020.11+git3.g87ee9469d

Name:           nqp-moarvm
Version:        %nqp_rev
Release:        1.1
Summary:        NQP
License:        Artistic-2.0
Group:          Development/Languages/Other
URL:            https://github.com/Raku/nqp/
Source:         http://raku-ci.org/test/12345/nqp-%{version}.tar.xz
Patch0:         nqp-test-log.diff
BuildRequires:  moarvm-devel >= 2020.11+git47.g1c7358004
BuildRequires:  perl(YAML::Tiny)
Requires:       moarvm >= 2020.11+git47.g1c7358004
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
%ifarch s390x
BuildRequires:  libffi-devel
%endif

%description
This is "Not Quite Perl" -- a compiler for a subset of Raku used
to implement a full Raku compiler. This package provides NQP running
on the MoarVM virtual machine.

%prep
%setup -q -n nqp-%{nqp_rev}
%patch0 -p1

%build
perl Configure.pl --backends=moar --prefix=%{_usr} --with-moar=/usr/bin/moar --ignore-errors
make

%check
make test

%install
make install DESTDIR=$RPM_BUILD_ROOT

%files
%defattr(-,root,root)
%doc CREDITS
%license LICENSE
%{_bindir}/*
%{_datadir}/nqp

%changelog
