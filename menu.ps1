#Requires -Version 4.0

<#
.Synopsis
   This script is used to deploy a fresh install of DetectionLab

.DESCRIPTION
   This scripts runs a series of tests before running through the
   DetectionLab deployment. It checks:

   * If Packer and Vagrant are installed
   * If VirtualBox or VMware are installed
   * If the proper vagrant plugins are available
   * Various aspects of system health

   Post deployment it also verifies that services are installed and
   running.

   If you encounter issues, feel free to open an issue at
   https://github.com/clong/DetectionLab/issues

.PARAMETER ProviderName
  The Hypervisor you're using for the lab. Valid options are 'virtualbox' or 'vmware_desktop'

.PARAMETER PackerPath
  The full path to the packer executable. Default is C:\Hashicorp\packer.exe

.PARAMETER PackerOnly
  This switch skips deploying boxes with vagrant after being built by packer

.PARAMETER VagrantOnly
  This switch skips building packer boxes and instead downloads from Vagrant Cloud

.EXAMPLE
  build.ps1 -ProviderName virtualbox

  This builds the DetectionLab using virtualbox and the default path for packer (C:\Hashicorp\packer.exe)
.EXAMPLE
  build.ps1 -ProviderName vmware_desktop -PackerPath 'C:\packer.exe'

  This builds the DetectionLab using VMware and sets the packer path to 'C:\packer.exe'
.EXAMPLE
  build.ps1 -ProviderName vmware_desktop -VagrantOnly

  This command builds the DetectionLab using vmware and skips the packer process, downloading the boxes instead.
#>

[cmdletbinding()]
Param(
  # Vagrant provider to use.
  [ValidateSet('virtualbox', 'vmware_desktop')]
  [string]$ProviderName,
  [string]$PackerPath = 'C:\Hashicorp\packer.exe',
  [switch]$PackerOnly,
  [switch]$VagrantOnly,
  [string]$Option
)

$DL_DIR = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$LAB_HOSTS = @()

function install_checker {
  param(
    [string]$Name
  )
  $results = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' | Select-Object DisplayName
  $results += Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' | Select-Object DisplayName

  forEach ($result in $results) {
    if ($result -like "*$Name*") {
      return $true
    }
  }
  return $false
}

function check_packer {
  # Check for packer using Get-Command
  if ((Get-Command packer).Path) {
    $PackerPath = (Get-Command packer).Path
    Write-Output "Packer found at $PackerPath"
  }
  # Check for packer at $PackerPath
  if (!(Test-Path $PackerPath)) {
    Write-Error "Packer not found at $PackerPath"
    Write-Output 'Re-run the script setting the PackerPath parameter to the location of packer'
    Write-Output "Example: build.ps1 -PackerPath 'C:\packer.exe'"
    Write-Output 'Exiting..'
    break
  }
}
function check_vagrant {
  # Check if vagrant is in path
  try {
    Get-Command vagrant.exe -ErrorAction Stop | Out-Null
  }
  catch {
    Write-Error 'Vagrant was not found. Please correct this before continuing.'
    break
  }

  # Check Vagrant version >= 2.2.2
  [System.Version]$vagrant_version = $(vagrant --version).Split(' ')[1]
  [System.Version]$version_comparison = 2.2.2

  if ($vagrant_version -lt $version_comparison) {
    Write-Warning 'It is highly recommended to use Vagrant 2.2.2 or above before continuing'
  }
}

# Returns false if not installed or true if installed
function check_virtualbox_installed {
  Write-Host '[check_virtualbox_installed] Running..'
  if (install_checker -Name "VirtualBox") {
    Write-Host '[check_virtualbox_installed] Virtualbox found.'
    return $true
  }
  else {
    Write-Host '[check_virtualbox_installed] Virtualbox not found.'
    return $false
  }
}
function check_vmware_workstation_installed {
  Write-Host '[check_vmware_workstation_installed] Running..'
  if (install_checker -Name "VMware Workstation") {
    Write-Host '[check_vmware_workstation_installed] VMware Workstation found.'
    return $true
  }
  else {
    Write-Host '[check_vmware_workstation_installed] VMware Workstation not found.'
    return $false
  }
}

function check_vmware_vagrant_plugin_installed {
  Write-Host '[check_vmware_vagrant_plugin_installed] Running..'
  if (vagrant plugin list | Select-String 'vagrant-vmware-workstation') {
    Write-Host 'The vagrant VMware Workstation plugin is no longer supported.'
    Write-Host 'Please upgrade to the VMware Desktop plugin: https://www.vagrantup.com/docs/vmware/installation.html'
    return $false
  }
  if (vagrant plugin list | Select-String 'vagrant-vmware-desktop') {
    Write-Host '[check_vmware_vagrant_plugin_installed] Vagrant VMware Desktop plugin found.'
    return $true
  }
  else {
    Write-Host 'VMware Workstation is installed, but the Vagrant plugin is not.'
    Write-Host 'Visit https://www.vagrantup.com/vmware/index.html#buy-now for more information on how to purchase and install it'
    Write-Host 'VMware Workstation will not be listed as a provider until the Vagrant plugin has been installed.'
    Write-Host 'NOTE: The plugin does not work with trial versions of VMware Workstation'
    return $false
  }
}

function list_providers {
  [cmdletbinding()]
  param()

  Write-Host 'Available Providers: '
  if (check_virtualbox_installed) {
    $VirtualBoxInstalled = $true
    Write-Host '[*] virtualbox available'
  }
  if (check_vmware_workstation_installed) {
    if (check_vmware_vagrant_plugin_installed) {
      $VMwareInstalled = $true
      Write-Host '[*] vmware_desktop available'
    }
  }
  if ((-Not ($VirtualBoxInstalled)) -and (-Not ($VMwareInstalled))) {
    Write-Error 'You need to install a provider such as VirtualBox or VMware Workstation to continue.'
    break
  }
  if (($VirtualBoxInstalled) -and (-Not ($VMwareInstalled))) {
    Write-Host '[*] Only VirtualBox found installed. Proceeding with virtualbox as provider.'
    $ProviderName = 'virtualbox'
  }
  if ((-Not ($VirtualBoxInstalled)) -and ($VMwareInstalled)) {
    Write-Host '[*] Only VMware Workstation found installed. Proceeding with vmware_desktop as provider.'
    $ProviderName = 'vmware_desktop'
  }
  while (-Not ($ProviderName -eq 'virtualbox' -or $ProviderName -eq 'vmware_desktop')) {
    $ProviderName = Read-Host 'Which provider would you like to use?'
    Write-Debug "ProviderName = $ProviderName"
    if (-Not ($ProviderName -eq 'virtualbox' -or $ProviderName -eq 'vmware_desktop')) {
      Write-Error "Please choose a valid provider. $ProviderName is not a valid option"
    }
  }
  return $ProviderName
}

function get_lab_hosts {
  $script:LAB_HOSTS += foreach ($line in Get-Content $DL_DIR\Vagrant\Vagrantfile | Select-String -Pattern '^ {1,}config.vm.define' | Out-String) 
  {
    foreach ($box in $line.Trim().Split([Environment]::NewLine)) 
    {
      ($box.Trim().Split('"')[1]).Where({ $null -ne $_ })
    }
  }
}

function get_running_hosts {
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  $script:LAB_HOSTS = foreach ($box in ((vagrant status) | Select-String -Pattern "  running"))
  { 
    ($box|Out-String).Split(' ')[0].Trim()
  }
}

function get_snapshot_list {
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  Write-Host '[snapshot_list] Checking snapshots'
  $script:SNAPSHOT_LIST = ((vagrant snapshot list) | Get-Unique)
}

function preflight_checks {
  Write-Host '[preflight_checks] Running..'
  # Check to see that no boxes exist
  if (-Not ($VagrantOnly)) {
    Write-Host '[preflight_checks] Checking if Packer is installed'
    check_packer

    # Check Packer Version against known bad
    Write-Host '[preflight_checks] Checking for bad packer version..'
    [System.Version]$PackerVersion = $(& $PackerPath "--version")
    [System.Version]$PackerKnownBad = 1.1.2

    if ($PackerVersion -eq $PackerKnownBad) {
      Write-Error 'Packer 1.1.2 is not supported. Please upgrade to a newer version and see https://github.com/hashicorp/packer/issues/5622 for more information.'
      break
    }
  }
  if (!($PackerOnly)) {
    Write-Host '[preflight_checks] Checking if Vagrant is installed'
    check_vagrant

    Write-Host '[preflight_checks] Checking for pre-existing boxes..'
    if ((Get-ChildItem "$DL_DIR\Boxes\*.box").Count -gt 0) {
      Write-Host 'You seem to have at least one .box file present in the Boxes directory already. If you would like fresh boxes downloaded, please remove all files from the Boxes directory and re-run this script.'
    }

    # Check to see that no vagrant instances exist
    Write-Host '[preflight_checks] Checking for vagrant instances..'
    $CurrentDir = Get-Location
    Set-Location "$DL_DIR\Vagrant"
    if (($(vagrant status) | Select-String -Pattern "created \(|running \(|poweroff \(").Count -ne ($LAB_HOSTS).Count) {
      Write-Error 'You appear to have already created at least one Vagrant instance. This script does not support already created instances. Please either destroy the existing instances or follow the build steps in the README to continue.'
      break
    }
    Set-Location $CurrentDir

    # Check available disk space. Recommend 80GB free, warn if less
    Write-Host '[preflight_checks] Checking disk space..'
    $drives = Get-PSDrive | Where-Object {$_.Provider -like '*FileSystem*'}
    $drivesList = @()

    forEach ($drive in $drives) {
      if ($drive.free -lt 80GB) {
        $DrivesList = $DrivesList + $drive
      }
    }

    if ($DrivesList.Count -gt 0) {
      Write-Output "The following drives have less than 80GB of free space. They should not be used for deploying DetectionLab"
      forEach ($drive in $DrivesList) {
        Write-Output "[*] $($drive.Name)"
      }
      Write-Output "You can safely ignore this warning if you are deploying DetectionLab to a different drive."
    }

    # Ensure the vagrant-reload plugin is installed
    Write-Host '[preflight_checks] Checking if vagrant-reload is installed..'
    if (-Not (vagrant plugin list | Select-String 'vagrant-reload')) {
      Write-Output 'The vagrant-reload plugin is required and not currently installed. This script will attempt to install it now.'
      (vagrant plugin install 'vagrant-reload')
      if ($LASTEXITCODE -ne 0) {
        Write-Error 'Unable to install the vagrant-reload plugin. Please try to do so manually and re-run this script.'
        break
      }
    }

    # Ensure the vagrant-vbguest plugin is installed
    Write-Host '[preflight_checks] Checking if vagrant-vbguest is installed for virtualbox..'
    if (-Not (vagrant plugin list | Select-String 'vagrant-vbguest')) {
      Write-Output 'The vagrant-vbguest plugin is required and not currently installed. This script will attempt to install it now.'
      (vagrant plugin install 'vagrant-vbguest')
      if ($LASTEXITCODE -ne 0) {
        Write-Error 'Unable to install the vagrant-vbguest plugin. Please try to do so manually and re-run this script.'
        break
      }
    }
  }
  Write-Host '[preflight_checks] Finished.'
}

function packer_build_box {
  param(
    [string]$Box
  )

  Write-Host "[packer_build_box] Running for $Box"
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Packer"
  Write-Output "Using Packer to build the $BOX Box. This can take 90-180 minutes depending on bandwidth and hardware."
  $env:PACKER_LOG=1
  $env:PACKER_LOG_PATH="$DL_DIR\Packer\packer.log"
  &$PackerPath @('build', "--only=$PackerProvider-iso", "$box.json")
  Write-Host "[packer_build_box] Finished for $Box. Got exit code: $LASTEXITCODE"

  if ($LASTEXITCODE -ne 0) {
    Write-Error "Something went wrong while attempting to build the $BOX box."
    Write-Output "To file an issue, please visit https://github.com/clong/DetectionLab/issues/"
    break
  }
  Set-Location $CurrentDir
}

function move_boxes {
  Write-Host "[move_boxes] Running.."
  Move-Item -Path $DL_DIR\Packer\*.box -Destination $DL_DIR\Boxes
  if (-Not (Test-Path "$DL_DIR\Boxes\windows_10_$PackerProvider.box")) {
    Write-Error "Windows 10 box is missing from the Boxes directory. Quitting."
    break
  }
  if (-Not (Test-Path "$DL_DIR\Boxes\windows_2016_$PackerProvider.box")) {
    Write-Error "Windows 2016 box is missing from the Boxes directory. Quitting."
    break
  }
  Write-Host "[move_boxes] Finished."
}

function vagrant_up_host {
  param(
    [string]$VagrantHost
  )
  Write-Host "[vagrant_up_host] Running for $VagrantHost"
  Write-Host "Attempting to bring up the $VagrantHost host using Vagrant"
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  set VAGRANT_LOG=info
  &vagrant.exe @('up', $VagrantHost, '--provider', "$ProviderName") 2>&1 | Out-File -FilePath ".\logs\vagrant_up_$VagrantHost.log"
  Set-Location $CurrentDir
  Write-Host "[vagrant_up_host] Finished for $VagrantHost. Got exit code: $LASTEXITCODE"
  return $LASTEXITCODE
}

function vagrant_reload_host {
  param(
    [string]$VagrantHost
  )
  Write-Host "[vagrant_reload_host] Running for $VagrantHost"
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  &vagrant.exe @('reload', $VagrantHost, '--provision') 2>&1 | Out-File -FilePath ".\logs\vagrant_up_$VagrantHost.log" -Append
  Set-Location $CurrentDir
  Write-Host "[vagrant_reload_host] Finished for $VagrantHost. Got exit code: $LASTEXITCODE"
  return $LASTEXITCODE
}

function vagrant_halt_host {
  param(
    [string]$VagrantHost
  )
  Write-Host "[vagrant_halt_host] Running for $VagrantHost"
  Write-Host "Attempting to shutdown the $VagrantHost host using Vagrant"
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  set VAGRANT_LOG=info
  &vagrant.exe @('halt', $VagrantHost) 2>&1 | Out-File -FilePath ".\logs\vagrant_halt_$VagrantHost.log"
  Set-Location $CurrentDir
  Write-Host "[vagrant_halt_host] Finished for $VagrantHost. Got exit code: $LASTEXITCODE"
  return $LASTEXITCODE
}

function vagrant_destroy_host {
  param(
    [string]$VagrantHost
  )
  Write-Host "[vagrant_destroy_host] Running for $VagrantHost"
  Write-Host "Attempting to delete the $VagrantHost host using Vagrant"
  $CurrentDir = Get-Location
  Set-Location "$DL_DIR\Vagrant"
  set VAGRANT_LOG=info
  &vagrant.exe @('destroy', '-f', $VagrantHost) 2>&1 | Out-File -FilePath ".\logs\vagrant_destroy_$VagrantHost.log"
  Set-Location $CurrentDir
  Write-Host "[vagrant_destroy_host] Finished for $VagrantHost. Got exit code: $LASTEXITCODE"
  return $LASTEXITCODE
}

function download {
  param(
    [string]$URL,
    [string]$PatternToMatch,
    [switch]$SuccessOn401

  )
  Write-Host "[download] Running for $URL, looking for $PatternToMatch"
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $wc = New-Object System.Net.WebClient
  try
  {
    $result = $wc.DownloadString($URL)
    if ($result -like "*$PatternToMatch*") {
      Write-Host "[download] Found $PatternToMatch at $URL"
      return $true
    }
    else {
      Write-Host "[download] Could not find $PatternToMatch at $URL"
      return $false
    }
  }
  catch
  {
    if ($_.Exception.InnerException.Response.StatusCode -eq 401 -and $SuccessOn401.IsPresent)
    {
      return $true
    }
    else
    {
      Write-Host "Error occured on webrequest: $_"
      return $false
    }
  }
}

function post_build_checks {

  Write-Host '[post_build_checks] Running Splunk Check.'
  #$SPLUNK_CHECK = download -URL 'https://172.16.163.105:8000/en-US/account/login?return_to=%2Fen-US%2F' -PatternToMatch 'This browser is not supported by Splunk'
  Write-Host "[post_build_checks] Splunk Result: $SPLUNK_CHECK"

  Write-Host '[post_build_checks] Running Fleet Check.'
  #$FLEET_CHECK = download -URL 'https://172.16.163.105:8412' -PatternToMatch 'Kolide Fleet'
  Write-Host "[post_build_checks] Fleet Result: $FLEET_CHECK"

  Write-Host '[post_build_checks] Running MS ATA Check.'
  #$ATA_CHECK = download -URL 'https://172.16.163.103' -SuccessOn401
  Write-Host "[post_build_checks] ATA Result: $ATA_CHECK"

  if ($SPLUNK_CHECK -eq $false) {
    Write-Warning 'Splunk failed post-build tests and may not be functioning correctly.'
  }
  if ($FLEET_CHECK -eq $false) {
    Write-Warning 'Fleet failed post-build tests and may not be functioning correctly.'
  }
  if ($ATA_CHECK -eq $false) {
    Write-Warning 'MS ATA failed post-build tests and may not be functioning correctly.'
  }
}

function main {
  param(
    [Parameter(Position=0)]
    [string]$VagrantAction,
    [Parameter(Position=1)]
    [string]$SnapshotAction
  )

  get_lab_hosts

  if ($VagrantAction -eq 'up') {
    # Run check functions
    preflight_checks
  
    # If no ProviderName was provided, get a provider
    if ($ProviderName -eq $Null -or $ProviderName -eq "") {
      $ProviderName = list_providers
    }
  
    # Set Provider variable for use deployment functions
    if ($ProviderName -eq 'vmware_desktop') {
      $PackerProvider = 'vmware'
    }
    else {
      $PackerProvider = 'virtualbox'
    }

    # Build Packer Boxes
    if (!($VagrantOnly)) {
      packer_build_box -Box 'windows_2016'
      packer_build_box -Box 'windows_10'
      # add packer_build_box for securityonion and pfsense
      # Move Packer Boxes
      move_boxes
    }
  
    if (!($PackerOnly)) {
        # Vagrant up each box and attempt to reload one time if it fails
        forEach ($VAGRANT_HOST in $LAB_HOSTS) {
          Write-Host "[main] Running vagrant_up_host for: $VAGRANT_HOST"
          $result = vagrant_up_host -VagrantHost $VAGRANT_HOST
          Write-Host "[main] vagrant_up_host finished. Exitcode: $result"
          if ($result -eq '0') {
            Write-Output "Good news! $VAGRANT_HOST was built successfully!"
          }
          else {
            Write-Warning "Something went wrong while attempting to build the $VAGRANT_HOST box."
            Write-Output "Attempting to reload and reprovision the host..."
            Write-Host "[main] Running vagrant_reload_host for: $VAGRANT_HOST"
            $retryResult = vagrant_reload_host -VagrantHost $VAGRANT_HOST
            if ($retryResult -ne 0) {
              Write-Error "Failed to bring up $VAGRANT_HOST after a reload. Exiting"
              break
            }
          }
          Write-Host "[main] Finished for: $VAGRANT_HOST"
        }
     }
  }
  elseif ($VagrantAction -eq 'halt') {
    Write-Host "[main] Checking current environment for running hosts"
    get_running_hosts
    forEach ($VAGRANT_HOST in $LAB_HOSTS) {
      Write-Host "[main] Running vagrant_halt_host for: $VAGRANT_HOST"
      $result = vagrant_halt_host -VagrantHost $VAGRANT_HOST
      Write-Host "[main] vagrant_halt_host finished. Exitcode: $result"
      if ($result -eq '0') {
        Write-Output "Good news! $VAGRANT_HOST was stopped successfully!"
      }
      else {
        Write-Warning "Something went wrong while attempting to stop the $VAGRANT_HOST box."
        Write-Output "Attempting to stop the host again..."
        Write-Host "[main] Running vagrant_halt_host for: $VAGRANT_HOST"
        $retryResult = vagrant_halt_host -VagrantHost $VAGRANT_HOST
        if ($retryResult -ne 0) {
          Write-Error "Failed to stop $VAGRANT_HOST after second attempt. Exiting"
          break
        }
      }
      Write-Host "[main] Finished for: $VAGRANT_HOST"
    }
  }
  elseif ($VagrantAction -eq 'snapshot') {
    Write-Host "[main] Checking current environment for snapshots"
    get_snapshot_list
    if ($SnapshotAction -eq 'list') {
      if ( $script:SNAPSHOT_LIST | Select-String -Pattern "No snapshots have been taken yet" ) {
      Write-Error "No snapshots have been taken in current environment"
      #Write-Host $script:SNAPSHOT_LIST
      break
      }
    }
    break
    forEach ($VAGRANT_HOST in $LAB_HOSTS) {
      Write-Host "[main] Running vagrant_halt_host for: $VAGRANT_HOST"
      $result = vagrant_halt_host -VagrantHost $VAGRANT_HOST
      Write-Host "[main] vagrant_halt_host finished. Exitcode: $result"
      if ($result -eq '0') {
        Write-Output "Good news! $VAGRANT_HOST was stopped successfully!"
      }
      else {
        Write-Warning "Something went wrong while attempting to stop the $VAGRANT_HOST box."
        Write-Output "Attempting to stop the host again..."
        Write-Host "[main] Running vagrant_halt_host for: $VAGRANT_HOST"
        $retryResult = vagrant_halt_host -VagrantHost $VAGRANT_HOST
        if ($retryResult -ne 0) {
          Write-Error "Failed to stop $VAGRANT_HOST after second attempt. Exiting"
          break
        }
      }
      Write-Host "[main] Finished for: $VAGRANT_HOST"
    }
  }
  elseif ($VagrantAction -eq 'destroy') {
    Write-Host "[main] Checking current environment for any hosts"
    get_lab_hosts
    forEach ($VAGRANT_HOST in $LAB_HOSTS) {
      Write-Host "[main] Running vagrant_destroy_host for: $VAGRANT_HOST"
      $result = vagrant_destroy_host -VagrantHost $VAGRANT_HOST
      Write-Host "[main] vagrant_destroy_host finished. Exitcode: $result"
      if ($result -eq '0') {
        Write-Output "Good news! $VAGRANT_HOST was deleted successfully!"
      }
      else {
        Write-Warning "Something went wrong while attempting to delete the $VAGRANT_HOST box."
        Write-Output "Attempting to delete the host again..."
        Write-Host "[main] Running vagrant_destroy_host for: $VAGRANT_HOST"
        $retryResult = vagrant_destroy_host -VagrantHost $VAGRANT_HOST
        if ($retryResult -ne 0) {
          Write-Error "Failed to delete $VAGRANT_HOST after second attempt. Exiting"
          break
        }
      }
      Write-Host "[main] Finished for: $VAGRANT_HOST"
    }
  }
  
    # Update accordingly
    #Write-Host "[main] Running post_build_checks"
    #post_build_checks
    #Write-Host "[main] Finished post_build_checks"
}

function SnapshotMenu{
  Clear-Host
  Do
  {
    Write-Host -Object '*******************************'
    Write-Host -Object "Security Onion Snapshot Options" -ForegroundColor Blue
    Write-Host -Object '*******************************'
    Write-Host -Object ''
    Write-Host -Object '1.  List Snapshots      - List snapshots within current environment'
    Write-Host -Object ''
    Write-Host -Object '2.  Take A Snapshot     - Take a snapshot of the current environment'
    Write-Host -Object ''
    Write-Host -Object 'M.  Menu'
    Write-Host -Object ''
    Write-Host -Object 'Q.  Quit'
    $Snapshot = Read-Host -Prompt '(1-2, M to Main Menu, or Q to Quit)'

    switch($Snapshot) {
      1
      {
        $VagrantOnly = $true
        main 'snapshot' 'list'
        Set-Location "$DL_DIR"
        Exit
      }
      2
      {
        $VagrantOnly = $true
        Set-Location "$DL_DIR"
        Exit
      }
      M
      {
        Menu
        Exit
      }
      Q
      {
        cd $DL_DIR
        Exit
      }
    }
  }  
  until ($Snapshot -eq 'q')
}

function HaltMenu{
  Clear-Host
  Do
  {
    Write-Host -Object '***************************'
    Write-Host -Object "Security Onion Halt Options" -ForegroundColor Blue
    Write-Host -Object '***************************'
    Write-Host -Object ''
    Write-Host -Object '1.  Halt Current Env  - Destroy all machines in current environment'
    Write-Host -Object ''
    Write-Host -Object '2.  Halt All Envs     - Destroy machines in all environments'
    Write-Host -Object ''
    Write-Host -Object 'M.  Menu'
    Write-Host -Object ''
    Write-Host -Object 'Q.  Quit'
    $HaltMenu = Read-Host -Prompt '(1-2, M to Main Menu, or Q to Quit)'

    switch($HaltMenu) {
      1
      {
        $VagrantOnly = $true
        main 'halt'
        Remove-Item $DL_DIR\Vagrant\Vagrantfile
        Set-Location "$DL_DIR"
        Exit
      }
      2
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Minimal $DL_DIR\Vagrant\Vagrantfile
        main 'halt'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Basic $DL_DIR\Vagrant\Vagrantfile
        main 'halt'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Distributed $DL_DIR\Vagrant\Vagrantfile
        main 'halt'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Lab $DL_DIR\Vagrant\Vagrantfile
        main 'halt'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_All $DL_DIR\Vagrant\Vagrantfile
        main 'halt'
        Remove-Item $DL_DIR\Vagrant\Vagrantfile
        Set-Location "$DL_DIR"
        Exit
      }
      M
      {
        Clear-Host
        Menu
        Exit
      }
      Q
      {
        cd $DL_DIR
        Clear-Host
        Exit
      }
    }
  }  
  until ($HaltMenu -eq 'q')
}

function DestroyMenu{
  Clear-Host
  Do
  {
    Write-Host -Object '******************************'
    Write-Host -Object "Security Onion Destroy Options" -ForegroundColor Blue
    Write-Host -Object '******************************'
    Write-Host -Object ''
    Write-Host -Object '1.  Destroy Current Env  - Destroy all machines in current environment'
    Write-Host -Object ''
    Write-Host -Object '2.  Destroy All Envs     - Destroy machines in all environments'
    Write-Host -Object ''
    Write-Host -Object 'M.  Menu'
    Write-Host -Object ''
    Write-Host -Object 'Q.  Quit'
    $DestroyMenu = Read-Host -Prompt '(1-2, M to Main Menu, or Q to Quit)'

    switch($DestroyMenu) {
      1
      {
        $VagrantOnly = $true
        main 'destroy'
        Remove-Item $DL_DIR\Vagrant\Vagrantfile
        Set-Location "$DL_DIR"
        Exit
      }
      2
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Minimal $DL_DIR\Vagrant\Vagrantfile
        main 'destroy'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Basic $DL_DIR\Vagrant\Vagrantfile
        main 'destroy'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Distributed $DL_DIR\Vagrant\Vagrantfile
        main 'destroy'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Lab $DL_DIR\Vagrant\Vagrantfile
        main 'destroy'
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_All $DL_DIR\Vagrant\Vagrantfile
        main 'destroy'
        Remove-Item $DL_DIR\Vagrant\Vagrantfile
        Set-Location "$DL_DIR"
        Exit
      }
      M
      {
        Clear-Host
        Menu
        Exit
      }
      Q
      {
        cd $DL_DIR
        Clear-Host
        Exit
      }
    }
  }  
  until ($DestroyMenu -eq 'q')
}

function Menu {
  Clear-Host
  Do
  # TODO:
  #  - add HH setup
  #  - add One stop SOC setup
  #  - add pagination (to help menu first)
  #  - Vagrantfile must exist
  #  - 99 runs delete twice (not on error but legit 0)
  {
    if ( !$Option -or $Option -gt 5 ) {
    Write-Host -Object '*********************************'
    Write-Host -Object "Security Onion Deployment Options" -ForegroundColor Blue
    Write-Host -Object '*********************************'
    Write-Host -Object ''
    Write-Host -Object '1.  Minimal Install     - Single Security Onion Instance (Standalone)'
    Write-Host -Object ''
    Write-Host -Object '2.  Standard Install    - Single Security Onion Instance (Standalone)'
    Write-Host -Object ''
    Write-Host -Object '3.  Distributed Demo    - Analyst, Master, Heavy, Forward, pfSense, Apt-Cacher NG, Web, DC'
    Write-Host -Object ''
    Write-Host -Object '4.  Windows Lab         - Security Onion (Standalone), pfSense, RTO, DC, WEF, Win10, Guacamole'
    Write-Host -Object ''
    Write-Host -Object '5.  All Machines        - The whole enchilada! Please have at least 64GB of RAM to attempt'
    Write-Host -Object ''
    Write-Host -Object '6.  Halt Options'
    Write-Host -Object ''
    Write-Host -Object '99. Destroy Options'
    Write-Host -Object ''
    Write-Host -Object 'H.  Help'
    Write-Host -Object ''
    Write-Host -Object 'Q.  Quit'
    $Option = Read-Host -Prompt '(1-5, 6 to halt, 99 to destroy, H for Help, or Q to Quit)'
    }

    switch($Option) {
      1
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Minimal $DL_DIR\Vagrant\Vagrantfile
        main 'up'
        Set-Location "$DL_DIR"
        Exit
      }
      2
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Basic $DL_DIR\Vagrant\Vagrantfile
        main 'up'
        Set-Location "$DL_DIR"
        Exit
      }
      3
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Distributed $DL_DIR\Vagrant\Vagrantfile
        main 'up'
        Set-Location "$DL_DIR"
        Exit
      }
      4
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_Lab $DL_DIR\Vagrant\Vagrantfile
        main 'up'
        Set-Location "$DL_DIR"
        Exit
      }
      5
      {
        $VagrantOnly = $true
        Copy-Item $DL_DIR\Vagrant\Vagrantfile_All $DL_DIR\Vagrant\Vagrantfile
        main 'up'
        Set-Location "$DL_DIR"
        Exit
      }
      6
      {
        HaltMenu
      }
      7
      {
        SnapshotMenu
      }
      99
      {
        DestroyMenu
      }
      H
      {
        Write-Host -Object '*******************'
        Write-Host -Object "Security Onion Help" -ForegroundColor Blue
        Write-Host -Object '*******************'
        Write-Host -Object ''
        Write-Host -Object '1.  Minimal Install     - Single Security Onion Instance (Standalone)'
        Write-Host -Object '                          NAT network'
        Write-Host -Object '                          2 interfaces: mgmt0 & promisc0'
        Write-Host -Object '                          Setup to use minimal hardware: 2 CPU & 4GB RAM'
        Write-Host -Object '                          Self installing. Ready to go after the initial build!'
        Write-Host -Object '                          WARNING: Suricata NIDS and Bro/Zeek logs ONLY!'
        Write-Host -Object ''
        Write-Host -Object '2.  Standard Install    - Single Security Onion Instance (Standalone)'
        Write-Host -Object '                          NAT network'
        Write-Host -Object '                          2 interfaces: mgmt0 & promisc0'
        Write-Host -Object '                          Setup to use basic requirements for eval: 4 CPU & 8GB RAM'
        Write-Host -Object '                          Self installing. Ready to go after the initial build!'
        Write-Host -Object '                          Full Elastic pipeline and standard integrations'
        Write-Host -Object ''
        Write-Host -Object '3.  Distributed Demo    - Analyst, Master, Heavy, Forward, pfSense, Apt-Cacher NG, Web, DC'
        Write-Host -Object '                          172.16.163.0/24 network'
        Write-Host -Object '                          Vanilla installation without any setup'
        Write-Host -Object '                          Learn how a distributed Security Onion installation works'
        Write-Host -Object '                          Integrate any endpoint solution for testing'
        Write-Host -Object ''
        Write-Host -Object '4.  Windows Lab         - Security Onion (Standalone), pfSense, RTO, DC, WEF, Win10, Guacamole'
        Write-Host -Object '                          172.16.163.0/24 network'
        Write-Host -Object '                          Guacamole front-end to access all machines from a single interface'
        Write-Host -Object '                          Security Onion setup complete w/Elastic Features enabled'
        Write-Host -Object '                          Red Team Operator machine using Redcloud and educational ransomware'
        Write-Host -Object '                          Sysmon, Autoruns, Atomic Red Team, Mimikatz installed on Windows'
        Write-Host -Object '                          All Windows logs forwarded to WEF box via GPO'
        Write-Host -Object '                          WEF forwards all logs to Security Onion via Winlogbeat'
        Write-Host -Object ''
        Write-Host -Object '5.  All Machines        - The whole enchilada! Please have at least 64GB of RAM to attempt'
        Write-Host -Object '                          172.16.163.0/24 network'
        Write-Host -Object '                          Analyst, Master, Heavy, Forward, pfSense,'
        Write-Host -Object '                          Apt-Cacher NG, Web, DC, WEF, Win10'
        Write-Host -Object '                          Mimic an entire network with a single `vagrant up`'
        Write-Host -Object '                          IF YOU HAVE THE RESOURCES! NOT FOR THE FAINT OF HEART!'
        Write-Host -Object ''
        Write-Host -Object '6.  Halt Menu           - Choose to shut down current env or all running envs'
        Write-Host -Object ''
        Write-Host -Object '99. Destroy Menu        - Choose to destroy current env or all machines in every env'
        Pause
        Clear-Host
      }
      Q
      {
        cd $DL_DIR
        Clear-Host
        Exit
      }
    }
  }  
  until ($Option -eq 'q')
}

# Call selection menu here for boxes based on Vagrantfile
Menu
Clear-Host
break