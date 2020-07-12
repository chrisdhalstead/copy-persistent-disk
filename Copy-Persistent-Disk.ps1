
#########################################################################################
# Script to copy non profile data from a Persistent Disk to a network share
# It will also detect a FSLogix Profile and copy the data back
# Josh Spencer / Chris Halstead - VMware
# There is NO support for this script - it is provided as is
# 
# Version 1.5 - July 12, 2020
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
$sLogPath = $sLogPath + "\Logs"
#Create Log Directory if it doesn't exist
if (!(Test-Path $sLogPath)){New-Item -ItemType Directory -Path $sLogPath -Force}
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
Add-Content $sLogFile -Value $vbcrlf
$sLogTitle = "Starting Script as $un from $scomputer*************************************"
Add-Content $sLogFile -Value $sLogTitle
#Set path to copy the extra files to
$script:CopyPath = [Environment]::GetFolderPath("MyDocuments")+"\ExtrasFromPersistentDisk"
#########################################################################################

#Update Below ***************************************

#Enter path of file share where user data can be copied
$pddestfs = "\\hzn-79-cs1-cdh.betavmweuc.com\PDData\$un"

#End Update **********************************

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

#Get Remote Path
Write-Log -Message "Remote Path: $pddestfs"

#Get Persistent Disk path
$PDPath = $script:pd +":\"
Write-Log -Message "Persistent Disk Path: $pdpath"

#Check if remote folder for Persistent Disk exists
if (!(Test-Path $pddestfs))  
{
  Write-Log("$tab $pddestfs not found-creating folder")
  New-Item -ItemType Directory -Path $pddestfs
  #Doing initial sync from the Persistent Disk
  Write-Log("$tab Doing Intial Sync from Persistent Disk")
  Get-ChildItem -Path $pdpath | % {Copy-Item $_.FullName "$pddestfs" -Recurse -Force -Exclude @("Personality","Personality.bak")}

}
else
{  
   
#Check to see if the folder is empty - if it is do an initial sync of a data except profile data
$checklocalfolder = Get-ChildItem -Path $pddestfs

if ($checklocalfolder.count -eq 0) {

  Write-Log("$tab Doing Intial Sync from Persistent Disk")
  Get-ChildItem -Path $pdpath | % {Copy-Item $_.FullName "$script:pddestfs" -Recurse -Force -Exclude @("Personality","Personality.bak")}

} else {
  
  #Get SHA256 Hash of each file in the Persistent Disk
write-log -message "Getting file hashes from Persistent Disk Directory"
try{$script:PDDocs = Get-ChildItem –Path $PDPath -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Persistent Disk File $_" }

#Get SHA256 Hash of each file in the Remote Directory
write-log -message "Getting file hashes from Remote Directory"
try{$script:LocalDocs = Get-ChildItem –Path $pddestfs -Recurse | foreach-object {Get-FileHash –Path $_.FullName}}
catch{write-log -message "Error Getting Hash of Remote File $_"}

#Get the files that are different or do not exist
write-log -message "Comparing Local and Remote File Hashes"
$diffs = Compare-Object -ReferenceObject $PDDocs -DifferenceObject $script:LocalDocs -Property Hash -PassThru

#Filter out only files that are different or do not exist in the Local Directory as well as any profile folders
$pddiffs = $diffs | ?{($_.SideIndicator -eq '<=' -and $_.path -notlike $script:pd + ":\personality*")}

#If both directories are the same - exit
if(!$pddiffs)
{
  write-log -Message "Directories are the same - exiting"
  write-log -Message "Setting Flag File"
  out-file $script:pddestfs"\PD-flag.txt"
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

    $fixedfile = $sfile.path
    $filearray = $fixedfile.split($PDPath)
    $destfile = "$pddestfs\$filearray[1]"
    
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
}
}

Function Copy-Back {

  #Get Remote Path
  Write-Log -Message "Remote Path: $pddestfs"
  
  #Get Local Path
  Write-Log -Message "Local Path: $script:CopyPath"
   
  #Check if local folder for Persistent Disk Data exists
  if (!(Test-Path $script:CopyPath))  
  {
    Write-Log("$tab $script:CopyPath not found-creating folder")
    New-Item -ItemType Directory -Path $script:CopyPath
    #Doing initial sync from the Persistent Disk
    Write-Log("$tab Doing Intial Sync from Remote Folder")
    Get-ChildItem -Path $pddestfs | % {Copy-Item $_.FullName "$script:CopyPath" -Recurse -Force}
  
    #Add Flag File
    out-file $pddestfs"\PD-CopyBack-flag.txt"
  }
  else
  {  
     
    Write-Log("$tab Doing Sync from Remote Folder")
    Get-ChildItem -Path $pddestfs | % {Copy-Item $_.FullName "$script:CopyPath" -Recurse -Force}
  
    #Add Flag File
    out-file $pddestfs"\PD-CopyBack-flag.txt"
    
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
 
#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message "Starting Execution of Script******************************************"

#Look for a local Persistent Disk
FindPersistentDisk

if ($script:pd -eq "NOT_FOUND") {
  #No Persistent Disk Found 
  #Check remote location for coped PD Data
    if (Test-Path $pddestfs)  
    {
      #Check to see if the remote folder exists
          if (Test-Path $pddestfs)  
            {
              if (Test-Path $pddestfs"\PD-flag.txt")

                {
                  if (Test-Path $pddestfs"\PD-CopyBack-flag.txt")

                  {

                       #Flag file found indicating copy back done - exiting
                       write-log("Flag file found indicating copy back done - exiting")  
                       write-log("Finishing Script***********************************************************") 

                  }
                  else 
                  {

                    #Flag file found indicating ready to copy back data- copy data to local profile
                    write-log("Flag file found indicating copy back ready - copying to local directory - $script:copypath")  
                    Copy-Back
                    write-log("Finishing Script***********************************************************") 

                  }  
               
                }
                else 
                {
                  #Flag file not found - not ready to copy skip
                  write-log("Flag file not found - skipping copy back")  
                  write-log("Finishing Script***********************************************************")  

                }

            }

    }       
    else 
    {
      write-log("Remote Folder not found*")  
      write-log("Finishing Script***********************************************************")  

    }

} 

else {

  if(Test-Path $pddestfs"\PD-flag.txt")
  {
    write-log("Found Flag File - Skipping")
    write-log("Finishing Script***********************************************************")
  }

  else 
  {
  #Compare and sync Persistent Disk To Network Share
  Compare-and-Sync
  write-log("Finishing Script***********************************************************")  

  }


}


