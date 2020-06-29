#########################################################################################
# Script to copy non profile data from a Persistent Disk to the local user profile
# Josh Spencer / Chris Halstead - VMware
# There is NO support for this script - it is provided as is
# #
# Version 1.1 - May 20, 2020
##########################################################################################

#Create Log File
$Tab = [char]9
$VbCrLf = “`r`n” 
$un = $env:USERNAME #Local Logged in User
$pool = Get-ItemProperty -Path 'HKCU:\Volatile Environment' 'ViewClient_Broker_Farm_ID'
$poolname = $pool.ViewClient_Broker_Farm_ID
$sComputer = $env:COMPUTERNAME #Local Computername
$sLogName = "copypd#$un#$poolname.log" #Log File Name
$sLogPath = $PSScriptRoot #Current Directory
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
Add-Content $sLogFile -Value $vbcrlf
$sLogTitle = "Starting Script as $un from $scomputer*************************************"
Add-Content $sLogFile -Value $sLogTitle

Function Write-Log {
  [CmdletBinding()]
  Param(
  
  [Parameter(Mandatory=$True)]
  [System.Object]
  $Message

  )
  $Stamp = (Get-Date).toString("MM/dd/yyyy HH:mm:ss")
  $Line = "$Stamp $Level $Message"

  $isWritten = $false

  do {
      try {
          Add-Content $sLogFile -Value $Line
          $isWritten = $true
          }
      catch {}
  } until ($isWritten)
     
  }

Function Compare-and-Sync {

#Get local profile path
$mydocs = [Environment]::GetFolderPath("MyDocuments")
$LocalPath = $mydocs + "\DatafromPD-$un"
Write-Log -Message "Local Path: $LocalPath"

#Get Persistent Disk path
$PDPath = $script:pd +":\"
Write-Log -Message "Persistent Disk Path: $pdpath"

#Check if local folder for Persistent Disk exists
if (!(Test-Path $localpath))  {
  Write-Log("$tab $localpath not found-creating folder")
  New-Item -ItemType Directory -Path $localpath 
  #Doing initial sync of the non-profile data from the Persistent Disk
  Write-Log("$tab Doing Intial Sync from Persistent Disk")
  Get-ChildItem -Path $pdpath | % {Copy-Item $_.FullName "$localpath" -Recurse -Force -Exclude @("Personality","Personality.bak")}
  #exit 
  break
}
else
{  
  #Check to see if the folder is empty - if it is do an initial sync of a data except profile data
  $checklocalfolder = Get-ChildItem -Path $localpath

  if ($checklocalfolder.count -eq 0) {

    Write-Log("$tab Doing Intial Sync from Persistent Disk")
    Get-ChildItem -Path $pdpath | % {Copy-Item $_.FullName "$localpath" -Recurse -Force -Exclude @("Personality","Personality.bak")}

  }

}

#Get SHA256 Hash of each file in the Persistent Disk
write-log -message "Getting file hashes from Persistent Directory"
try{$script:PDDocs = Get-ChildItem –Path $PDPath -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Persistent Disk File $_" }

#Get SHA256 Hash of each file in the Local Directory
write-log -message "Getting file hashes from Local Directory"
try{$script:LocalDocs = Get-ChildItem –Path $LocalPath -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Local File $_"}

#Get the files that are different or do not exist
write-log -message "Comparing Local and Remote File Hashes"
$diffs = Compare-Object -ReferenceObject $PDDocs -DifferenceObject $LocalDocs -Property Hash -PassThru

#Filter out only files that are different or do not exist in the Local Directory as well as any profile folders
$pddiffs = $diffs | ?{($_.SideIndicator -eq '<=' -and $_.path -notlike $script:pd + ":\personality*")}

#If both directories are the same - exit
  if(!$pddiffs)
  {
    write-log -Message "Directories are the same - exiting"
    Write-Log -Message "Finishing Script******************************************************"
    Exit
  }

$inumfiles = $personadiffs.count
write-log -Message "Copying $inumfiles files"

#Loop through each file in the list of differences
Foreach ($sfile in $pddiffs) 
    {
      $sfilehash = $sfile.Hash
      $sfilename = $sfile.path

      #Skip any of the Profile Directories on the Persistent Disk
      if ($sfilename -like $script:pd + ":\personality*")
      {
        #Go to the next item in the loop
        continue
      }

      #File to be copied
      Write-Log -Message "File to be copied: $sfilename Hash: $sfilehash"

      #Replace the remote path with the local path
      $destfile = $sfile.path -replace [Regex]::Escape("$PDPath"),[Regex]::Escape("$LocalPath")
      Write-Log -Message "$tab Destination Filename: $destfile"

      #Check if the file already exists - if not create a placeholder file in the location
      #This will prevent getting an error if the directory does not exist
      if (!(Test-Path $destfile))  {
        Write-Log("$tab File $destfile not found-creating placeholder")
        New-Item -ItemType File -Path $destfile -Force}
      
      #Overwrite the file in the destination 
      Write-Log -Message "$tab Copying $sfilename to $destfile"
      try{Copy-Item -Path $sfile.path -Destination $destfile -Force -Exclude @("Personality","Personality.bak")} Catch{write-log -message "Error Copying file $_"}
      if (Test-Path $destfile)  {
        Write-Log("$tab File $destfile copied")
             }
  }

}

Function FindPersistentDisk {

#List Local Volumes
 $drives = Get-Volume
 $script:pd = ""

#Loop through each drive
foreach ($dl in $drives) {

    $driveletter = $dl.DriveLetter
    $fn = $dl.filesystemlabel

    #Check if the label is caled PersistentDataDisk
    if ($fn -eq "PersistentDataDisk")  
        {
      #Check if the simvol.dat file is on the root of the drive
      if (Test-Path $driveletter":\simvol.dat")  {
        Write-Log("Drive $driveletter IS a Persistent Disk")
        $script:pd = $driveletter
          }
      else {
        #Not a Persistent Disk 
      }
   } else {
   #Not a Persistent Disk
    }

  }

  if ($script:pd -eq "") {
    #No Persistent Disk Found
    $script:pd = "NOT_FOUND"
    write-log("No Persistent Disk Found")
  }

 }

 Function AuditMode {







 }
 
#-----------------------------------------------------------[Execution]------------------------------------------------------------

$auditmode = $args[0]

Write-Log -Message "Starting Execution of Script******************************************"


#Look for a local Persistent Disk
FindPersistentDisk

if ($script:pd -eq "NOT_FOUND") {
  #No Persistent Disk Found - Exit
  write-log("Finishing Script***********************************************************")
  exit

}

#Check for audit mode
if ($auditmode.toupper() -eq "AUDIT")

{

  write-log -Message "Run auditing mode"
  write-log("Finishing Script***********************************************************")
  exit
}

#Compare and sync Persistent Disk Locally
Compare-and-Sync

write-log("Finishing Script***********************************************************")
