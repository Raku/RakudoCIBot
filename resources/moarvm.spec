#
# spec file for package moarvm
#
# Copyright (c) 2021 SUSE LLC
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

%global moar_rev <moar_rev>

Name:           moarvm
Version:        %moar_rev
Release:        2.1
Summary:        A virtual machine built especially for Rakudo
License:        Artistic-2.0
Group:          Development/Libraries/Other
URL:            http://moarvm.org
Source:         http://raku-ci.org/test/12345/%{moar_rev}-moar.tar.xz
# PATCH-FIX-OPENSUSE boo#1100677
Patch0:         reproducible.patch
BuildRequires:  perl(ExtUtils::Command)
BuildRequires:  pkgconfig(libffi)
%if 0%{?suse_version} >= 1550
BuildRequires:  pkgconfig(libtommath)
BuildRequires:  pkgconfig(libuv)
%endif
%if !0%{?rhel_version}
BuildRequires:  pkgconfig(libzstd)
%endif

%description
MoarVM (short for Metamodel On A Runtime Virtual Machine) is a runtime built
for the 6model object system. It is primarily aimed at running NQP and Rakudo,
but should be able to serve as a backend for any compilers built using
the NQP compiler toolchain.

%package devel
Summary:        MoarVM development headers and libraries
Group:          Development/Libraries/Other
Requires:       %{name} = %{version}
Requires:       pkgconfig(libffi)
%if 0%{?suse_version} >= 1550
Requires:       pkgconfig(libtommath)
Requires:       pkgconfig(libuv)
%endif
%if !0%{?rhel_version}
Requires:       pkgconfig(libzstd)
%endif

%description devel
MoarVM (Metamodel On A Runtime) development headers.

%prep
%setup -q -n %{moar_rev}-moar
%patch0 -p1

%build
extra_config_args=
%if 0%{?suse_version} >= 1550
extra_config_args+=" --has-libtommath --has-libuv"
%endif
%ifarch riscv64
extra_config_args+=" --c11-atomics"
%endif
CFLAGS="%{optflags}" \
perl Configure.pl --prefix=%{_usr} --libdir=%{_libdir} --debug --optimize=3 --has-libffi $extra_config_args
make NOISY=1 %{?_smp_mflags}

%install
%make_install
find %buildroot -type f \( -name '*.so' -o -name '*.so.*' \) -exec chmod 755 {} +
mkdir -p $RPM_BUILD_ROOT/%{_libdir}/moar/share

%files
%defattr(-,root,root)
%doc CREDITS Artistic2.txt docs
%license LICENSE
%{_bindir}/moar
%{_libdir}/libmoar*
%{_libdir}/moar
%{_datadir}/nqp

%files devel
%defattr(-,root,root)
%{_includedir}/*
%{_datadir}/pkgconfig/*

%changelog
