<#
.SYNOPSIS
Parses the Source directory, processes each file based on extension, then puts the resulting file in into the Desination.

.DESCRIPTION
The `gitops-build.ps1` script checks each file in the Source.  The processes the file based on the file name.  Template files are processed through the EPS module.  Specto files are only copied if the SpectoCommon AND SpectoSignature strings are in the file name.  All other files are simply copied.  Files whose path matches the Exclude regex are skipped.

.PARAMETER Source
The Directory that will be parsed recursively.

.PARAMETER Destination
The Directory that will store the resulting files.

.PARAMETER Exclude
A Regular Expression used to identify the files that should not be processed.  This is matched against the full path of the source file.

.PARAMETER TemplateExtension
If a file ends with this extension, it is considered a Template file to be processed through Invoke-EpsTemplate.  The TemplateExtension is removed from the destination file name.

.PARAMETER TemplateBinding
A hashtable that is passed into Invoke-EpsTemplate.  Variables in this hashtable are made available to the Template files.

.PARAMETER SpectoCommon
The string that identifies the common signature used to identify Specto files.  If a file contains this string in its name it will be processed through the Specto logic.  The Specto logic will check the end of the file name for the SpectoSignature, if it doesn't match, it is not copied.  If it does, it is copied with SpectoCommon and SpectoSignature removed from the name.

.PARAMETER SpectoSignature
The string used to identify a Specto file as one that needs to be copied.

.PARAMETER GitTag
The Tag that represents the build state.  Used in `git diff` call to determine the state of the file.

.INPUTS
System.IO.DirectoryInfo can be piped into Source.

.OUTPUTS
@(
    @{
        operation = "eps" # One of the following: eps, specto, copy
        source = @{
            # Attributes from Get-Item plus...
            DiffState = "Modified" # One of the following: Added, Modified, or Deleted
            Hash = # Result from Get-FileHash
        }
        epsDiff = # Diff between source and staged if the operation is eps and not secret
        currentBuild = @{
            # Attributes from Get-Item plus...
            Hash = # Result from Get-FileHash
        }
    }
)

.LINK
EPS ( Embedded PowerShell )
https://github.com/straightdave/eps

.COMPONENT
EPS
#>

#Requires -Modules @{ ModuleName="EPS"; ModuleVersion="1.0.0" }
[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [System.IO.DirectoryInfo]
    $Source,
    [Parameter(Mandatory=$true)]
    [ValidateScript({
        Test-Path $_ -IsValid
    })]
    [String]
    $Destination,
    [Regex]
    $Exclude = '^.*\.md$',
    [String]
    $TemplateExtension = ".eps1",
    [hashtable]
    $TemplateBinding = @{},
    [String]
    $SpectoCommon = ".specto",
    [String]
    $SpectoSignature,
    [String]
    $GitTag
)

# See https://github.com/straightdave/eps for more information
Import-Module EPS

$Returned = @()

If (Test-Path $Destination) {
    $DestinationDirectory = Get-Item $Destination
} Else {
    $DestinationDirectory = New-Item $Destination -ItemType Directory -Force
}

ForEach ($SourceFile in $(Get-ChildItem $Source -Recurse -File)) {
    $ReturnedElement = @{}
    $ReturnedElement.Source.File = $SourceFile
    $ReturnedElement.Source.Hash = Get-FileHash $ReturnedElement.Source.File
    If ($GitTag -and $(git status)) {
        $ReturnedElement.Source.DiffState = (git diff --name-status $GitTag HEAD $Source.FullName)[0]
    } ElseIf (git status) {
        $ReturnedElement.Source.DiffState = (git diff --name-status HEAD^ HEAD $Source.FullName)[0]
    } Else {
        Write-Warning $(git status)
    }
    If ($Exclude -and ($SourceFile.FullName -match $Exclude)) {
        $ReturnedElement.Operation = "Excluded"
        $Returned.Add($ReturnedElement)
        Continue
    }
    $DestinationFile = @{
        FullName = $SourceFile.FullName.Replace($Source.FullName, $DestinationDirectory.FullName)
        Directory = $SourceFile.Directory.FullName.Replace($Source.FullName, $DestinationDirectory.FullName)
    }
    If (-not $(Test-Path $DestinationFile.Directory)) {
        New-item $DestinationFile.Directory -ItemType Directory -Force 1>$null
    }
    If ($SourceFile.Name.EndsWith($TemplateExtension)) {
        $ReturnedElement.Operation = "Template"
        $DestinationFile.FullName = $DestinationFile.FullName.Replace($TemplateExtension, "")
        $ReturnedElement.CurrentBuild.File = Invoke-EpsTemplate -Path $SourceFile.FullName -Binding $TemplateBinding | New-Item -ItemType File -Path $DestinationFile.FullName -Force
        $ReturnedElement.CurrentBuild.Hash = Get-FileHash $ReturnedElement.CurrentBuild.File
        $ReturnedElement.TemplateDiff = Compare-Object $(Get-Content $SourceFile.FullName) $(Get-Content $DestinationFile.FullName)
    } ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
        $ReturnedElement.Operation = "Specto"
        If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
            $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon,"").Replace($SpectoSignature,"")
            $ReturnedElement.CurrentBuild.File = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru
            $ReturnedElement.CurrentBuild.Hash = Get-FileHash $ReturnedElement.CurrentBuild.File
        }
    } Else {
        $ReturnedElement.Operation = "Copy"
        $ReturnedElement.CurrentBuild.File = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru
        $ReturnedElement.CurrentBuild.Hash = Get-FileHash $ReturnedElement.CurrentBuild.File
    }
    $Returned.Add($ReturnedElement)
}

Return $Returned