#########################################################################################
# Script to copy non profile data from a Persistent Disk to the local user profile
# Josh Spencer / Chris Halstead - VMware
# There is NO support for this script - it is provided as is
# Usage....
#
# Version 1.0 - April 22, 2020
##########################################################################################

#Create Log File
$Tab = [char]9
$VbCrLf = “`r`n” 
$un = $env:USERNAME #Local Logged in User
$sComputer = $env:COMPUTERNAME #Local Computername
$sLogName = "copy-pd-$un.log" #Log File Name
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
$LocalPath = "C:\users\" + $un + "\Documents\DatafromPD-$un\"
Write-Log -Message "Local Path: $LocalPath"

#Get Persistent Disk path
$PDPath = $script:pd +":\"
Write-Log -Message "Persistent Disk Path: $pdpath"

if (!(Test-Path $localpath))  {
  Write-Log("$tab $localpath not found-creating folder")
  New-Item -ItemType Directory -Path $localpath 

  Write-Log("$tab Doing Intial Sync")
  
  Get-ChildItem -Path $pdpath | % {Copy-Item $_.FullName "$localpath" -Recurse -Force -Exclude @("Personality","Personality.bak")}

  break

}

#Get SHA256 Hash of each file in the Persistent Disk
write-log -message "Getting file hashes from Persona Directory"
try{$script:PMDocs = Get-ChildItem –Path $PDPath -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Persona File $_" }

#Get SHA256 Hash of each file in the Local Directory
write-log -message "Getting file hashes from Local Directory"
try{$script:LocalDocs = Get-ChildItem –Path $LocalPath -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Persona File $_"}

#Get the files that are different or do not exist
write-log -message "Comparing Local and Remote File Hashes"
$diffs = Compare-Object -ReferenceObject $PMDocs -DifferenceObject $LocalDocs -Property Hash -PassThru

#Filter out only files that are different or do not exist in the Local Directory
$personadiffs = $diffs | ?{ $_.SideIndicator -eq '<='}

#If both directories are the same - exit
  if(!$personadiffs)
  {
    write-log -Message "Directories are the same - exiting"
    Write-Log -Message "Finishing Script******************************************************"
    Exit
  }

$inumfiles = $personadiffs.count
write-log -Message "Copying $inumfiles files"

#Loop through each file in the list of differences
Foreach ($sfile in $personadiffs) 
    {
      $sfilehash = $sfile.Hash
      $sfilename = $sfile.path

      if ($sfilename -like $script:pd + ":\personality*")
      {

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
        New-Item -ItemType File -Path $destfile -Force
            }
      
      #Overwrite the file in the destination 
      Write-Log -Message "$tab Copying $sfilename to $destfile"
      try{Copy-Item -Path $sfile.path -Destination $destfile -Force -Exclude @("Personality","Personality.bak")} Catch{write-log -message "Error Copying file $_"}
      if (Test-Path $destfile)  {
        Write-Log("$tab File $destfile copied")
             }
  }

Write-Log -Message "Finishing Script******************************************************"

}

Function FindPersistentDisk {

 $drives = Get-Volume
 $script:pd = ""

 foreach ($dl in $drives) {

    $driveletter = $dl.DriveLetter
    $fn = $dl.filesystemlabel

    if ($fn -eq "PersistentDataDisk")  {
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

    $script:pd = "NOT_FOUND"
    write-log("No Persistent Disk Found")
  
  }

 }
 
#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message "Starting Execution of Script******************************************"

FindPersistentDisk

if ($script:pd -eq "NOT_FOUND") {
  
  write-log("Finishing Script***********************************************************")
  exit

}

write-log("Copy PD Data Locally")
Compare-and-Sync
write-log("Finishing Script***********************************************************")
