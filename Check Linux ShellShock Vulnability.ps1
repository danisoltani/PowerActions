<#
.MYNGC_REPORT

.LABEL
Check Linux ShellShock Vulnability

.DESCRIPTION
Check VMs for Linux ShellShock Vulnability.
#>

param
(
   [Parameter(Mandatory=$true)]
   [VMware.VimAutomation.ViCore.Types.V1.Inventory.Cluster]
   $Cluster,
   [Parameter(mandatory=$true)]
   [String]
   $Linux_Username,
   [Parameter(mandatory=$true)]
   [String]
   $Linux_Password
);

# Adjusted from Luc Dekens
# http://www.lucd.info/2014/09/28/powercli-linux-shellshock-vulnerability/#more-4813
# Script to find the Linux Shellshock vulnerability on VMs

function Get-VMShellShock{
<#
.SYNOPSIS  Check for ShellShock vulnerability
.DESCRIPTION The function will connect to all VMs, that run
  a Linux guest OS, to check if they are vulnerable for
  the ShellShock buug
.NOTES  Author:  Luc Dekens
.PARAMETER Location
  The function will check all VMs in this Location. This can
  be a Cluster, a Datacenter, a Folder, a Datastore...
.PARAMETER VM
  The function will check all VMs passed on this parameter.
.PARAMETER Credential
  The credential to logon to the Linux guest OS
.EXAMPLE
  PS> Get-VMShellShock -VM vm1 -Credential $cred
.EXAMPLE
  PS> Get-VMShellShock -Location $cluster -Credential $cred
#>
 
  [CmdletBinding()]
  param(
  [parameter(Mandatory=$true,ParameterSetName = "Location")]
  [VMware.VimAutomation.Sdk.Types.V1.VIObject]$Location,
  [parameter(Mandatory=$true,ParameterSetName = "VM")]
  [PSObject[]]$VM,
  [System.Management.Automation.PSCredential]$Credential
  )
 
  Begin{
    $exploits = @{
        'CVE_2014_6271' = 'x=''() { :;}; echo VULNERABLE'' bash -c :'
        'CVE_2014_7169' = 'env X=''() { (a)=>\'' bash -c "echo echo nonvuln" 2>/dev/null; [[ "$(cat echo 2> /dev/null)" == "nonvuln" ]] && echo "vulnerable" 2> /dev/null'
        'CVE_2014_7186' = 'bash -c ''true <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF <<EOF'' || echo "vulnerable"'
        'CVE_2014_7187' = '(for x in {1..200} ; do echo "for x$x in ; do :"; done; for x in {1..200} ; do echo done ; done) | bash || echo "vulnerable"'
    }
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
  }
 
  Process{
    if($PSCmdlet.ParameterSetName -eq "Location"){
      $vms = Get-VM -Location $entity | where {$_.GuestId -match "rhel|sles"}
    }
    elseif($PSCmdlet.ParameterSetName -eq "VM"){
      $vms = $VM| %{
        if($_ -is [System.String]){
          Get-VM -Name $_ | where {$_.GuestId -match "rhel|sles"}
        }
        else{
          $_
        }
      }
    }
 
    foreach($vm in $vms){
      $logon = "ok"
      $CVE_2014_6271 = $CVE_2014_7169 = $CVE_2014_7186 = $CVE_2014_7187 = $null
      if($vm.Guest.State -ne "notRunning"){
        $exploits.GetEnumerator() | %{
            Try{
              $result = Invoke-VMScript -VM $vm -ScriptText $_.Value -GuestCredential $Credential -ScriptType Bash -ErrorAction Stop
              Set-Variable -Name $_.Name -Value ($result.ScriptOutput -match "VULNERABLE")
            }
            Catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidGuestLogin]{
              $logon = "Guest logon failed"
            }
            Catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException]{
              if($error[0].Exception.Message -match "Failed to resolve host"){
                $logon = "Failed to resolve host"
              }
              else{
                $logon = $error[0].Exception.Message
              }
            }
            Catch{
              $logon = $error[0].Execption.Message
            }
        }
      }
      New-Object PSObject -Property @{
        VM = $vm.Name
        OS = $vm.GuestId
        "OS Full" = $vm.Guest.OSFullName
        "VMware Tools" = $vm.Guest.State
        Logon = $logon
        CVE_2014_6271 = $CVE_2014_6271
        CVE_2014_7169 = $CVE_2014_7169
        CVE_2014_7186 = $CVE_2014_7186
        CVE_2014_7187 = $CVE_2014_7187
      }
    }
  }
 
  End{
    $ProgressPreference = $oldProgressPreference
  }
}
 
$pswdSecure = ConvertTo-SecureString -String $Linux_Password -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Linux_username,$pswdSecure
 
Get-VMShellShock -Location $Cluster -Credential $cred |
Select VM,OS,"OS Full","VMware Tools",CVE_2014_6271,CVE_2014_7169,CVE_2014_7186,CVE_2014_7187,Logon 