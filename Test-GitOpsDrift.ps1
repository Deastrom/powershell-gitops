Function Test-GitOpsDrift {
    <#
    .SYNOPSIS
    Checks the Source Directory's Git Diff and uses that information to help determine drift in the
    Destination Directory.

    .DESCRIPTION
    Run Git Diff on the Source Directory then determines each file's Build Directory representation.
    Checks the Hash of the file in the Build Directory against the Destination Directory and, based
    on the Git Diff, writes a warning if the hashes don't match when they should, or match when they
    shouldn't, or don't exist when they should, or exist when they shouldn't.

    .PARAMETER Build
    The Directory which holds the built representations of the Source Directory.

    .PARAMETER Source
    The Directory which holds the source.

    .PARAMETER Destination
    The Directory which holds the built represenations as they exist on the target system. Use PSDrive
    to map remote systems.

    .PARAMETER GitTag
    Used in the Git Diff call. Not currently implemented as it is not supported in Deploy-GitOpsBuild.

    .PARAMETER Exclude
    Regex which determines files that should be skipped.

    .PARAMETER TemplateExtension
    The extension of template files, used to determine the name of the built representation.

    .PARAMETER SpectoCommon
    The string that indicates that a file is intended to be Specific To (SpecTo) a system.

    .PARAMETER SpectoSignature
    The string that indicates that a specto file is to be copied in this run.

    #>
    param(
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [Parameter()]
        [String]
        $Build = $env:TEMP,

        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [Parameter(Mandatory = $true)]
        [String]
        $Source,

        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        # [Parameter()]
        # [String]
        # $GitTag,

        [Parameter()]
        [Regex]
        $Exclude = '^.*\.md$',

        [Parameter()]
        [String]
        $TemplateExtension = ".eps1",

        [Parameter()]
        [String]
        $SpectoCommon = ".specto",

        [Parameter()]
        [String]
        $SpectoSignature
    )
    Process {
        If (-not $(Test-Path $Destination)) {
            Write-Error "$Destination directory not found."
        }
        $SourceDirectory = Get-Item $Source
        Write-Debug "$($SourceDirectory.FullName)"
        $BuildDirectory = Get-Item $Build
        $DestinationDirectory = Get-Item $Destination
        Push-Location $SourceDirectory
        Try {
            $GitSrcFiles = @{}
            If ($PSBoundParameters['GitTag']) {
                git diff --relative --name-status $GitTag HEAD `
                | Tee-Object -Variable GitStatusCmdOutput `
                | Write-Debug
            }
            Else {
                git diff --relative --name-status HEAD^ HEAD `
                | Tee-Object -Variable GitStatusCmdOutput `
                | Write-Debug
            }
            ForEach ($Line in $GitStatusCmdOutput) {
                $GitStatusArray = $Line.Split("`t")
                Write-Debug $GitStatusArray.Count
                If ($GitStatusArray.Count -eq 3) {
                    $GitSrcFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[2])
                    $GitSrcFile = $GitSrcFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                    $GitSrcFromFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[1])
                    $GitSrcFromFile = $GitSrcFromFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                    $GitSrcFiles["$GitSrcFile"] = @{
                        FullName = $GitSrcFileInfo.FullName
                        Parent = $GitSrcFileInfo.DirectoryName
                        FromFile  = $GitSrcFromFile
                        GitStatus = $GitStatusArray[0]
                    }
                }
                ElseIf ($GitStatusArray.Count -eq 2) {
                    $GitSrcFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[1])
                    Write-Debug "$($GitSrcFileInfo | Select-Object -Property *)"
                    $GitSrcFile = $GitSrcFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                    $GitSrcFiles["$GitSrcFile"] = @{
                        FullName = $GitSrcFileInfo.FullName
                        Parent = $GitSrcFileInfo.DirectoryName
                        FromFile  = $GitSrcFile
                        GitStatus = $GitStatusArray[0]
                    }
                }
            }
            Write-Debug "$($GitSrcFiles | ConvertTo-Json -Depth 100)"
            ForEach ($File in $($GitSrcFiles.GetEnumerator())) {
                If ($Exclude -and ($File.Key -match $Exclude)) {
                    Write-Verbose "$($File.Key) Excluded"
                    Continue
                }
                $BuildFile = @{
                    FullName = Join-Path -Path $BuildDirectory.FullName -ChildPath $File.Key
                    Directory = Join-Path -Path $BuildDirectory.FullName -ChildPath $File.Value.Parent.Replace("$($SourceDirectory.FullName)", "")
                }
                $DestinationFile = @{
                    FullName = Join-Path -Path $DestinationDirectory.FullName -ChildPath $File.Key
                    Directory = Join-Path -Path $DestinationDirectory.FullName -ChildPath $File.Value.Parent.Replace("$($SourceDirectory.FullName)", "")
                }
                If ($File.Key.EndsWith($TemplateExtension)) {
                    $BuildFile.FullName = $BuildFile.FullName.Replace($TemplateExtension, "")
                    $DestinationFile.FullName = $DestinationFile.FullName.Replace($TemplateExtension, "")
                } ElseIf ($File.Key.Contains($SpectoCommon)) {
                    If ($SpectoSignature -and ($File.Key.EndsWith($SpectoSignature))) {
                        $BuildFile.FullName = $BuildFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                        $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                    } Else {
                        Continue
                    }
                }
                $BuildFileHash = Get-FileHash $BuildFile.FullName -ErrorAction SilentlyContinue
                $DestinationFileHash = Get-FileHash $DestinationFile.FullName -ErrorAction SilentlyContinue
                Switch ($File.Value.GitStatus) {
                    'A' {
                        # addition of a file
                        Write-Verbose "$($File.Key) was Added since last build, $($DestinationFile.FullName) hash should be null."
                        If ($null -ne $DestinationFilehash) {
                            Write-Warning "$($File.Key) was added but $($DestinationFile.FullName) already exists."
                        }
                        Break
                    }
                    'D' {
                        # deletion of a file
                        Write-Warning "$($File.Key) was Deleted since last build, consider deleting $($DestinationFile.FullName)."
                        Break
                    }
                    'M' {
                        # modification of the contents or mode of a file
                        Write-Warning "$($File.Key) was Modified since last build, $($DestinationFile.FullName) shoudl be different than Source and overwritten."
                        If ($null -eq $DestinationFilehash) {
                            Write-Warning "$($File.Key) was Modified but $($DestinationFile.FullName) was not found."
                        } ElseIf ($BuildFileHash.Hash -eq $DestinationFileHash.Hash) {
                            Write-Warning "$($File.Key) was Modified but $($DestinationFile.FullName) matches the hash of the $($Buildfile.FullName) file. File may have already been deployed."
                        }
                        Break
                    }
                    'R' {
                        # renaming of a file
                        Write-Verbose "$($File.Key) has been renamed from $($File.Value.FromFile). $($DestinationFile.FullName) should not exist. Any file generated from $($Destination.FullName) should be considered for deletion."
                        If ($null -ne $DestinationFileHash) {
                            Write-Warning "$($File.Key) was renamed from $($File.Value.FromFile), but $($DestinationFile.FullName) already exists."
                        }
                        Write-Warning "$($File.Key) was renamed from $($File.Value.FromFile). Consider deleting any file that was generated from $($File.Value.FromFile)."
                    }
                    Default {
                        # Default
                        Write-Warning "$($File.Key) has a status of $($File.Value.GitStatus), which is not handled."
                    }
                }
            }
            ForEach ($SourceFile in $(Get-ChildItem $SourceDirectory.FullName -Recurse -File)) {
                If ($Exclude -and ($SourceFile.FullName -match $Exclude)) {
                    Write-Verbose "$($SourceFile.FullName) Excluded"
                    Continue
                }
                $SourceFileRelPath = $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                If ($GitSrcFiles.ContainsKey($SourceFileRelPath)) {
                    Write-Verbose "$SourceFileRelPath was already checked during Git Diff handling."
                    Continue
                }
                $BuildFile = @{
                    FullName  = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                    Directory = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.Directory.FullName.Replace($SourceDirectory.FullName, "")
                }
                $DestinationFile = @{
                    FullName  = Join-Path -Path $DestinationDirectory.FullName -ChildPath $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                    Directory = Join-Path -Path $DestinationDirectory.FullName -ChildPath $SourceFile.Directory.FullName.Replace($SourceDirectory.FullName, "")
                }
                If ($SourceFile.Name.EndsWith($TemplateExtension)) {
                    $BuildFile.FullName = $BuildFile.FullName.Replace($TemplateExtension, "")
                    $DestinationFile.FullName = $DestinationFile.FullName.Replace($TemplateExtension, "")
                }
                ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
                    If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
                        $BuildFile.FullName = $BuildFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                        $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                    } Else {
                        Continue
                    }
                }
                $BuildFileHash = Get-FileHash $BuildFile.FullName
                $DestinationFileHash = Get-FileHash $DestinationFile.FullName -ErrorAction SilentlyContinue
                Write-Verbose "$SourceFileRelPath has no changes since the last build. $($BuildFile.FullName) should match $($DestinationFile.FullName)."
                If ($null -eq $DestinationFileHash) {
                    Write-Warning "$SourceFileRelPath has no changes since the last build. $($DesinationFile.FullName) was not found."
                }
                ElseIf ($($DestinationFileHash.Hash) -ne $($BuildFileHash.Hash)) {
                    Write-Warning "$SourceFileRelPath has no changes since the last build. $($BuildFile.FullName) does not match $($DestinationFile.FullName)."
                }
            }
        }
        Finally {
            Pop-Location
        }
    }
}