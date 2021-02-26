#Requires -Modules @{ ModuleName="EPS"; ModuleVersion="1.0.0" }
Function Build-GitOpsSource {
    <#
    .SYNOPSIS
    Parses the Source directory, processes each file based on extension, then puts
    the resulting file in into the Build.

    .DESCRIPTION
    The 'Build-GitOpsSource' function checks each file in the Source.  The processes
    the file based on the file name.  Template files are processed through the
    EPS module.  Specto files are only copied if the SpectoCommon AND
    SpectoSignature strings are in the file name.  All other files are simply
    copied.  Files whose path matches the Exclude regex are skipped.

    .PARAMETER Source
    The Directory that will be parsed recursively.

    .PARAMETER Build
    The Directory that will store the resulting files.

    .PARAMETER Destination
    Not Used in this function. Added for splatting purposes.

    .PARAMETER Exclude
    A Regular Expression used to identify the files that should not be processed.
    This is matched against the full path of the source file.

    .PARAMETER TemplateExtension
    If a file ends with this extension, it is considered a Template file to be
    processed through Invoke-EpsTemplate.  The TemplateExtension is removed from
    the destination file name.

    .PARAMETER TemplateBinding
    A hashtable that is passed into Invoke-EpsTemplate.  Variables in this
    hashtable are made available to the Template files.

    .PARAMETER SpectoCommon
    The string that identifies the common signature used to identify Specto files.
    If a file contains this string in its name it will be processed through the Specto
    logic.  The Specto logic will check the end of the file name for the SpectoSignature,
    if it doesn't match, it is not copied.  If it does, it is copied with SpectoCommon
    and SpectoSignature removed from the name.

    .PARAMETER SpectoSignature
    The string used to identify a Specto file as one that needs to be copied.

    .PARAMETER WithTemplateDiff
    When used in combination with Verbose it includes the the output of
    `git diff --no-index Source Destination` when doing  This aids in the troublshooting
    of Template files.

    .LINK
    EPS ( Embedded PowerShell )
    https://github.com/straightdave/eps

    .COMPONENT
    EPS
    
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [String]
        $Source,
        [ValidateScript( {
                Test-Path $_ -IsValid -PathType Container
            })]
        [String]
        $Build = $env:TEMP,
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
        [Switch]
        $WithTemplateDiff
    )

    Process {
        Write-Verbose "Get the Directory Info for Source and Directory"
        $SourceDirectory = Get-Item -Path $Source
        Write-Verbose "Set Location to $Source to provide context for git commands."
        Push-Location $Source
        # See https://github.com/straightdave/eps for more information
        Write-Verbose "Import the EPS module which will be used for Template files with the $TemplateExtension extension."
        Import-Module EPS
        If (-not $(Test-Path $Build)) {
            New-Item $Build -ItemType Directory | Out-Null
        }
        $BuildDirectory = Get-Item -Path $Build
        try {
            ForEach ($SourceFile in $(Get-ChildItem $SourceDirectory.FullName -Recurse -File)) {
                Write-Verbose "Processing $SourceFile"
                If ($Exclude -and ($SourceFile.FullName -match $Exclude)) {
                    Write-Verbose "$($SourceFile.FullName) Excluded"
                    Continue
                }
                $BuildFile = @{}
                $BuildFile.FullName = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                $BuildFile.Directory = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.Directory.FullName.Replace($SourceDirectory.FullName, "")
                If (-not $(Test-Path $BuildFile.Directory)) {
                    New-item $BuildFile.Directory -ItemType Directory -Force | Out-Null
                }
                If ($SourceFile.Name.EndsWith($TemplateExtension)) {
                    $BuildFile.FullName = $BuildFile.FullName.Replace($TemplateExtension, "")
                    Write-Verbose "$($SourceFile.FullName) Templated to $($BuildFile.FullName)"
                    Invoke-EpsTemplate -Path $SourceFile.FullName -Binding $TemplateBinding | New-Item -ItemType File -Path $BuildFile.FullName -Force | Out-Null
                    If ($PSBoundParameters['WithTemplateDiff']) {
                        Write-Verbose @"
$(git diff --no-index $SourceFile.FullName $BuildFile.FullName)
"@
                    }
                }
                ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
                    If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
                        $BuildFile.FullName = $BuildFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                        Write-Verbose "$($SourceFile.FullName) Copied to $($BuildFile.FullName)"
                        Copy-Item $SourceFile.FullName -Destination $BuildFile.FullName -PassThru | Out-Null
                    } Else {
                        Write-Verbose "$($SourceFile.FullName) Skipped"
                    }
                }
                Else {
                    Write-Verbose "$($SourceFile.FullName) Copied to $($BuildFile.FullName)"
                    Copy-Item $SourceFile.FullName -Destination $BuildFile.FullName -PassThru | Out-Null
                }
            }
        }
        finally {
            Pop-Location
        }
    }
}