# @api private
# @summary Installs core python packages
#
# @example
#  include python::install
#
class python::install {

  $python_version = getparam(Class['python'], 'version')
  $python = $python_version ? {
    'system' => 'python',
    'pypy'   => 'pypy',
    /\A(python)?([0-9](\.?[0-9])+)/ => "python${1}",
    default  => "python${python::version}",
  }

  $pythondev = $facts['os']['family'] ? {
    'AIX'    => "${python}-devel",
    'RedHat' => "${python}-devel",
    'Debian' => "${python}-dev",
    'Suse'   => "${python}-devel",
    'Gentoo' => undef,
  }

  $pip_ensure = $python::pip ? {
    true    => 'present',
    false   => 'absent',
    default => $python::pip,
  }

  $venv_ensure = $python::virtualenv ? {
    true    => 'present',
    false   => 'absent',
    default => $python::virtualenv,
  }

  if $venv_ensure == 'present' {
    $dev_ensure = 'present'
    unless $python::dev {
      # Error: python2-devel is needed by (installed) python-virtualenv-15.1.0-2.el7.noarch
      # Python dev is required for virtual environment, but python environment is not required for python dev.
      notify { 'Python virtual environment is dependent on python dev': }
    }
  } else {
    $dev_ensure = $python::dev ? {
      true    => 'present',
      false   => 'absent',
      default => $python::dev,
    }
  }

  package { 'python':
    ensure => $python::ensure,
    name   => $python,
  }

  package { 'virtualenv':
    ensure  => $venv_ensure,
    require => Package['python'],
  }

  case $python::provider {
    'pip': {

      package { 'pip':
        ensure  => $pip_ensure,
        require => Package['python'],
      }

      if $pythondev {
        package { 'python-dev':
          ensure => $dev_ensure,
          name   => $pythondev,
        }
      }

      # Install pip without pip, see https://pip.pypa.io/en/stable/installing/.
      include 'python::pip::bootstrap'

      Exec['bootstrap pip'] -> File['pip-python'] -> Package <| provider == pip |>

      Package <| title == 'pip' |> {
        name     => 'pip',
        provider => 'pip',
      }
      Package <| title == 'virtualenv' |> {
        name     => 'virtualenv',
        provider => 'pip',
        require  => Package[$pythondev],
      }
    }
    'scl': {
      # SCL is only valid in the RedHat family. If RHEL, package must be
      # enabled using the subscription manager outside of puppet. If CentOS,
      # the centos-release-SCL will install the repository.
      $install_scl_repo_package = $::operatingsystem ? {
        'CentOS' => 'present',
        default  => 'absent',
      }

      package { 'centos-release-scl':
        ensure => $install_scl_repo_package,
        before => Package['scl-utils'],
      }
      package { 'scl-utils':
        ensure => 'latest',
        before => Package['python'],
      }

      # This gets installed as a dependency anyway
      # package { "${python::version}-python-virtualenv":
      #   ensure  => $venv_ensure,
      #   require => Package['scl-utils'],
      # }
      package { "${python}-scldevel":
        ensure  => $dev_ensure,
        require => Package['scl-utils'],
      }
      if $pip_ensure != 'absent' {
        exec { 'python-scl-pip-install':
          command => "${python::exec_prefix}easy_install pip",
          path    => ['/usr/bin', '/bin'],
          creates => "/opt/rh/${python::version}/root/usr/bin/pip",
          require => Package['scl-utils'],
        }
      }
    }
    'rhscl': {
      # rhscl is RedHat SCLs from softwarecollections.org
      if $::python::rhscl_use_public_repository {
        $scl_package = "rhscl-${::python::version}-epel-${::operatingsystemmajrelease}-${::architecture}"
        package { $scl_package:
          source   => "https://www.softwarecollections.org/en/scls/rhscl/${::python::version}/epel-${::operatingsystemmajrelease}-${::architecture}/download/${scl_package}.noarch.rpm",
          provider => 'rpm',
          tag      => 'python-scl-repo',
        }
      }

      Package <| title == 'python' |> {
        tag => 'python-scl-package',
      }

      Package <| title == 'virtualenv' |> {
        name => "${python}-python-virtualenv",
      }

      package { "${python}-scldevel":
        ensure => $dev_ensure,
        tag    => 'python-scl-package',
      }

      package { "${python}-python-pip":
        ensure => $pip_ensure,
        tag    => 'python-pip-package',
      }

      if $::python::rhscl_use_public_repository {
        Package <| tag == 'python-scl-repo' |>
        -> Package <| tag == 'python-scl-package' |>
      }

      Package <| tag == 'python-scl-package' |>
      -> Package <| tag == 'python-pip-package' |>
    }
    'anaconda': {
      $installer_path = '/var/tmp/anaconda_installer.sh'

      file { $installer_path:
        source => $::python::anaconda_installer_url,
        mode   => '0700',
      }
      -> exec { 'install_anaconda_python':
        command   => "${installer_path} -b -p ${::python::anaconda_install_path}",
        creates   => $::python::anaconda_install_path,
        logoutput => true,
      }
      -> exec { 'install_anaconda_virtualenv':
        command => "${::python::anaconda_install_path}/bin/pip install virtualenv",
        creates => "${::python::anaconda_install_path}/bin/virtualenv",
      }
    }
    default: {
      case $facts['os']['family'] {
        'AIX': {
          if "${python_version}" =~ /^python3/ { #lint:ignore:only_variable_string
            class { 'python::pip::bootstap':
                    version => 'pip3',
            }
          } else {
            package { 'python-pip':
              ensure   => $pip_ensure,
              require  => Package['python'],
              provider => 'yum',
            }
          }
          if $pythondev {
            package { 'python-dev':
              ensure   => $dev_ensure,
              name     => $pythondev,
              alias    => $pythondev,
              provider => 'yum',
            }
          }

        }
        default: {
          package { 'pip':
            ensure  => $pip_ensure,
            require => Package['python'],
          }
          if $pythondev {
            package { 'python-dev':
              ensure => $dev_ensure,
              name   => $pythondev,
              alias  => $pythondev,
            }
          }

        }
      }

      case $facts['os']['family'] {
        'RedHat': {
          if $pip_ensure != 'absent' {
            if $python::use_epel == true {
              include 'epel'
              Class['epel'] -> Package['pip']
            }
          }
          if ($venv_ensure != 'absent') and ($::operatingsystemrelease =~ /^6/) {
            if $python::use_epel == true {
              include 'epel'
              Class['epel'] -> Package['virtualenv']
            }
          }

          $virtualenv_package = "${python}-virtualenv"
        }
        'Debian': {
          if fact('lsbdistcodename') == 'trusty' {
            $virtualenv_package = 'python-virtualenv'
          } else {
            $virtualenv_package = 'virtualenv'
          }
        }
        'Gentoo': {
          $virtualenv_package = 'virtualenv'
        }
        default: {
          $virtualenv_package = 'python-virtualenv'
        }
      }

      if "${::python::version}" =~ /^python3/ { #lint:ignore:only_variable_string
        $pip_category = undef
        $pip_package = 'python3-pip'
      } elsif ($::osfamily == 'RedHat') and (versioncmp($::operatingsystemmajrelease, '7') >= 0) {
        $pip_category = undef
        $pip_package = 'python2-pip'
      } elsif $::osfamily == 'Gentoo' {
        $pip_category = 'dev-python'
        $pip_package = 'pip'
      } else {
        $pip_category = undef
        $pip_package = 'python-pip'
      }

      Package <| title == 'pip' |> {
        name     => $pip_package,
        category => $pip_category,
      }

      Package <| title == 'virtualenv' |> {
        name => $virtualenv_package,
      }
    }
  }

  if $python::manage_gunicorn {
    $gunicorn_ensure = $python::gunicorn ? {
      true    => 'present',
      false   => 'absent',
      default => $python::gunicorn,
    }

    package { 'gunicorn':
      ensure => $gunicorn_ensure,
      name   => $python::gunicorn_package_name,
    }
  }
}
