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
    {
        "Source": "", //Source Directory full path,
        "Destination": "", //Destination Directory full path,
        "Files": [
            {
                "Operation": "",//One of Template, Specto, Copy, or Excluded,
                "Source": {
                    "FileHash": {},//Results from `Get-FileHash`,
                    "GitDiffState": ""//Results from `git diff --name-status`
                },
                "CurrentBuild": {
                    "FileHash": {} //Results from `Get-FileHash`
                },
                "TemplateDiff": [] //Results from `git diff --no-index` if WithTemplateDiff switch is included
            }
        ]
    }

    .LINK
    EPS ( Embedded PowerShell )
    https://github.com/straightdave/eps

    .COMPONENT
    EPS
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [String]
        $Source,
        [ValidateScript( {
                Test-Path $_ -IsValid -PathType Container
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

    Process {
        Write-Verbose "Set Location to $Source to provide context for git commands."
        Push-Location $Source
        # See https://github.com/straightdave/eps for more information
        Write-Verbose "Import the EPS module which will be used for Template files with the $TemplateExtension extension."
        Import-Module EPS
        Write-Verbose "Get the Directory Info for Source and Directory"
        $SourceDirectory = Get-Item -Path $Source
        If (-not $(Test-Path $Destination)) {
            New-Item $Destination -ItemType Directory 1>$null
        }
        $DestinationDirectory = Get-Item -Path $Destination
        $Returned = [ordered]@{
            Source = $SourceDirectory.FullName
            Destination = $DestinationDirectory.FullName
            Files = New-Object 'Collections.Generic.List[hashtable]'
        }
        try {
            Write-Verbose "Test that git is installed and available."
            git --version 1>$null
            ForEach ($SourceFile in $(Get-ChildItem $SourceDirectory.FullName -Recurse -File)) {
                Write-Verbose "Processing $SourceFile"
                Write-Verbose "Initial ReturnedElement and get FileHash for $SourceFile."
                $ReturnedElement = @{
                    Operation    = $Null
                    Source       = @{
                        FileHash = Get-FileHash $SourceFile
                    }
                    CurrentBuild = @{}
                }
                If ($GitTag -and $(git status)) {
                    Write-Verbose "Setting ReturnedElement.Source.GitDiffState with 'git diff --name-status $GitTag HEAD $($SourceFile.FullName)'"
                    $ReturnedElement.Source.GitDiffState = git diff --name-status $GitTag HEAD $SourceFile.FullName
                }
                ElseIf ($(git status)) {
                    Write-Verbose "Setting ReturnedElement.Source.GitDiffState with 'git diff --name-status HEAD^ HEAD $($SourceFile.FullName)'"
                    $ReturnedElement.Source.GitDiffState = git diff --name-status HEAD^ HEAD $SourceFile.FullName
                }
                If ($Exclude -and ($SourceFile.FullName -match $Exclude)) {
                    $ReturnedElement.Operation = "Excluded"
                    Write-Verbose "$($SourceFile.FullName) Excluded"
                    $Returned.Add($ReturnedElement)
                    Continue
                }
                $DestinationFile = @{
                    FullName  = $($SourceFile.FullName.Replace($Returned.Source, $Returned.Destination))
                    Directory = $($SourceFile.Directory.FullName.Replace($Returned.Source, $Returned.Destination))
                }
                If (-not $(Test-Path $DestinationFile.Directory)) {
                    New-item $DestinationFile.Directory -ItemType Directory -Force 1>$null
                }
                If ($SourceFile.Name.EndsWith($TemplateExtension)) {
                    $ReturnedElement.Operation = "Template"
                    $DestinationFile.FullName = $DestinationFile.FullName.Replace($TemplateExtension, "")
                    Write-Verbose "$($SourceFile.FullName) Templated to $($DestinationFile.FullName)"
                    $ReturnedElement.CurrentBuild.FileHash = Invoke-EpsTemplate -Path $SourceFile.FullName -Binding $TemplateBinding | New-Item -ItemType File -Path $DestinationFile.FullName -Force | Get-FileHash
                    If ($WithTemplateDiff) {
                        $ReturnedElement.TemplateDiff = $(git diff --no-index $SourceFile.FullName $DestinationFile.FullName)
                    }
                }
                ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
                    $ReturnedElement.Operation = "Specto"
                    If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
                        $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                        Write-Verbose "$($SourceFile.FullName) Copied to $($DestinationFile.FullName)"
                        $ReturnedElement.CurrentBuild.FileHash = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru | Get-FileHash
                    } Else {
                        Write-Verbose "$($SourceFile.FullName) Skipped"
                    }
                }
                Else {
                    $ReturnedElement.Operation = "Copy"
                    Write-Verbose "$($SourceFile.FullName) Copied to $($DestinationFile.FullName)"
                    $ReturnedElement.CurrentBuild.FileHash = Copy-Item $SourceFile.FullName -Destination $DestinationFile.FullName -PassThru | Get-FileHash
                }
                $ReturnedElement.Source.FileHash.Path = $ReturnedElement.Source.FileHash.Path.Replace($Returned.Source, "")
                If ($ReturnedElement.CurrentBuild.FileHash.Path) {
                    $ReturnedElement.CurrentBuild.FileHash.Path = $ReturnedElement.CurrentBuild.FileHash.Path.Replace($Returned.Destination,"")
                }
                $Returned.Files.Add($ReturnedElement)
            }
            Write-Output $Returned
        }
        finally {
            Pop-Location
        }
    }
}