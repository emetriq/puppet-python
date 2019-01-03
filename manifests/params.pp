# @api private
# @summary The python Module default configuration settings.
#
class python::params {
  $ensure                 = 'present'
  $version                = 'system'
  $pip                    = 'present'
  $dev                    = 'absent'
  $virtualenv             = 'absent'
  $gunicorn               = 'absent'
  $manage_gunicorn        = true
  $provider               = undef
  $valid_versions         = undef

  if $::osfamily == 'RedHat' {
    if $::operatingsystem != 'Fedora' {
      $use_epel           = true
    } else {
      $use_epel           = false
    }
  } else {
    $use_epel             = false
  }

  $gunicorn_package_name = $::osfamily ? {
    'RedHat' => 'python-gunicorn',
    default  => 'gunicorn',
  }

  $rhscl_use_public_repository = true

  $anaconda_installer_url = 'https://repo.anaconda.com/archive/Anaconda3-5.2.0-Linux-x86_64.sh'
  $anaconda_install_path = '/opt/python'
}
