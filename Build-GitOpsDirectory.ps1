#Requires -Modules @{ ModuleName="EPS"; ModuleVersion="1.0.0" }
Function Build-GitOpsDirectory {
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

    .PARAMETER WithTemplateDiff
    Include the the output of `git diff --no-index Source Destination` when doing templating.  This aids in the troublshooting of Template files.
    
    .INPUTS
    System.IO.DirectoryInfo can be piped into Source.
    
    .OUTPUTS
    [
        {
            "Operation": "Template", //One of the following... Template, Specto, Copy, Excluded
            "Source": {
                "File": {}, //Output from Get-Item
                "Hash": {}, //Output from Get-FileHash
                "GitStatus": "" //Output from Git Diff --name-status
            },
            "CurrentBuild": {
                "File": {}, //Output from Get-Item
                "Hash": {} //Output from Get-FileHash
            }
        }
    ]
    
    .LINK
    EPS ( Embedded PowerShell )
    https://github.com/straightdave/eps
    
    .COMPONENT
    EPS
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.IO.DirectoryInfo]
        $Source,
        [ValidateScript({
            Test-Path $_ -IsValid
        })]
        [String]
        $Destination = $env:TEMP,
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
        $GitTag,
        [Switch]
        $WithTemplateDiff
    )
    
    Push-Location $Source
    # See https://github.com/straightdave/eps for more information
    Import-Module EPS
    try {
        git --version
    } catch {
        Write-Error "git is required."
    }
    try {
        If (Test-Path $Destination) {
            $DestinationDirectory = Get-Item $Destination
        } Else {
            $DestinationDirectory = New-Item $Destination -ItemType Directory -Force
        }

        $Returned = [ordered]@{
            Source = $Source.FullName
            Destination = $DestinationDirectory.FullName
            Files = New-Object 'Collections.Generic.List[hashtable]'
        }
            
        ForEach ($SourceFile in $(Get-ChildItem $Source -Recurse -File)) {
            $ReturnedElement = @{
                Operation = $Null
                Source = @{
                    File = Get-FileHash $SourceFile
                }
                CurrentBuild = @{}
            }
            If ($GitTag -and $(git status)) {
                $ReturnedElement.GitDiffState = git diff --name-status $GitTag HEAD $Source.FullName
            } ElseIf ($(git status)) {
                $ReturnedElement.GitDiffState = git diff --name-status HEAD^ HEAD $Source.FullName
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
                $ReturnedElement.CurrentBuild.File = Invoke-EpsTemplate -Path $SourceFile.FullName -Binding $TemplateBinding | New-Item -ItemType File -Path $DestinationFile.FullName -Force | Get-FileHash
                If ($WithTemplateDiff) {
                    $ReturnedElement.TemplateDiff = $(git diff --no-index $SourceFile.FullName $DestinationFile.FullName)
                }
            } ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
                $ReturnedElement.Operation = "Specto"
                If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
                    $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon,"").Replace($SpectoSignature,"")
                    $ReturnedElement.CurrentBuild.File = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru | Get-FileHash
                }
            } Else {
                $ReturnedElement.Operation = "Copy"
                $ReturnedElement.CurrentBuild.File = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru | Get-FileHash
            }
            $Returned.Files.Add($ReturnedElement)
        }
        Write-Output $Returned
    } finally {
        Pop-Location
    }
}