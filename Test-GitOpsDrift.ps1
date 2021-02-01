Function Test-GitOpsDrift {
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

        [Parameter()]
        [System.Management.Automation.Runspaces.PSSession]
        $ToSession,

        [Parameter()]
        [String]
        $GitTag,

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
        $InvCmdParams = @{}
        If ($PSBoundParameters['ToSession']) {
            $InvCmdParams.Session = $ToSession
        }
        If (-not $(Invoke-Command -ScriptBlock { Test-Path $using:Destination } @InvCmdParams)) {
            Write-Error "$Destination directory not found."
        }
        $SourceDirectory = Get-Item $Source
        Write-Debug "$($SourceDirectory.FullName)"
        $BuildDirectory = Get-Item $Build
        $DestinationDirectory = Invoke-Command -ScriptBlock { Get-Item $using:Destination } @InvCmdParams
        Push-Location $SourceDirectory
        Try {
            $Files = @{}
            If ($PSBoundParameters['GitTag']) {
                git diff --relative --name-status $GitTag HEAD | Tee-Object -Variable GitStatusCmdOutput
            }
            Else {
                git diff --relative --name-status HEAD^ HEAD | Tee-Object -Variable GitStatusCmdOutput
            }
            ForEach ($Line in $GitStatusCmdOutput) {
                $GitStatusArray = $Line.Split("`t")
                Write-Debug $GitStatusArray.Count
                If ($GitStatusArray.Count -eq 3) {
                    $GitSrcFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[2])
                    Write-Debug "$($GitSrcFileInfo | Select-Object -Property *)"
                    $GitSrcFile = $GitSrcFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                    $GitSrcFromFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[1])
                    $Files["$GitSrcFile"] = @{
                        FullName = $GitSrcFileInfo.FullName
                        Parent = $GitSrcFileInfo.DirectoryName
                        FromFile  = $GitSrcFromFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                        GitStatus = $GitStatusArray[0]
                    }
                }
                ElseIf ($GitStatusArray.Count -eq 2) {
                    $GitSrcFileInfo = [System.IO.FileInfo](Join-Path $SourceDirectory $GitStatusArray[1])
                    Write-Debug "$($GitSrcFileInfo | Select-Object -Property *)"
                    $GitSrcFile = $GitSrcFileInfo.FullName.Replace("$($SourceDirectory.FullName)", "")
                    $Files["$GitSrcFile"] = @{
                        FullName = $GitSrcFileInfo.FullName
                        Parent = $GitSrcFileInfo.DirectoryName
                        FromFile  = $GitSrcFile
                        GitStatus = $GitStatusArray[0]
                    }
                }
            }
            Write-Debug "$($Files | ConvertTo-Json -Depth 100)"
            ForEach ($File in $($Files.GetEnumerator())) {
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
                $DestinationFileHash = Invoke-Command -ScriptBlock { Get-FileHash $using:DestinationFile.FullName -ErrorAction SilentlyContinue } @InvCmdParams
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
                        If ($null -ne $DestinationFilehash) {
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
                $SourceFileRelPath = $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                If ($Files.ContainsKey($SourceFileRelPath)) {
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
                $DestinationFileHash = Invoke-Command -ScriptBlock { Get-FileHash $using:DestinationFile.FullName -ErrorAction SilentlyContinue } @InvCmdParams
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