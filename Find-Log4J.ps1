function Find-Log4J
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [Switch]
        $Repair
    )
    
    Add-Type -AssemblyName "System.IO.Compression"
    Add-Type -AssemblyName "System.IO.Compression.FileSystem"

    $jarString = '*log4j-core-2*.jar'

    $fsRoots = (Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path $_.Root }).Root

    $affectedJarList = foreach ($root in $fsRoots)
    {
        Write-Verbose "Searching drive: [$root]"
        Get-ChildItem -Path $root -File -Filter $jarString -Recurse -ErrorAction SilentlyContinue
    }

    if ($null -eq $affectedJarList)
    {
        Write-Verbose -Verbose "Couldn't find any jar files on this system."
    }
    else
    {
        $tempDirName = 'log4j_' + -join ([char[]]@(97..122) | Get-Random -Count 6)
        Write-Verbose "Generated new temp dir name: [$tempDirName]"
        $tempDir = New-Item -Path $env:TEMP -Name $tempDirName -ItemType Directory
        Write-Verbose "Created temp dir at: [$($tempDir.FullName)]"

        foreach ($jar in $affectedJarList)
        {
            $jarPatched = $false
            Write-Verbose -Verbose "Working on [$($jar.FullName)]"
            $jarZipPath = Join-Path -Path $tempDir.FullName -ChildPath "$($jar.BaseName + '.zip')"
            Write-Verbose "Generated zip path [$jarZipPath]"
            $jarBakPath = $jar.FullName + '.bak'
            Write-Verbose "Generated bak path [$jarBakPath]"

            
            if (!(Test-Path -Path $jarBakPath))
            {
                Write-Verbose 'Copying jar backup'
                Copy-Item -Path $jar.FullName -Destination $jarBakPath
            }

            Write-Verbose 'Copying jar to temp as zip'
            Copy-Item -Path $jar.FullName -Destination $jarZipPath

            Write-Verbose 'Opening zip...'
            $jarZip = [System.IO.Compression.ZipFile]::Open($jarZipPath, [System.IO.Compression.ZipArchiveMode]::Update)

            if ($null -ne $jarZip)
            {
                Write-Verbose 'Looking for jndilookup class...'
                $jndiClass = $jarZip.GetEntry('org/apache/logging/log4j/core/lookup/JndiLookup.class')
                if (($null -ne $jndiClass) -and ($Repair))
                {
                    Write-Verbose 'Deleting...'
                    $jndiClass.Delete()
                    $jndiClass = $jarZip.GetEntry('org/apache/logging/log4j/core/lookup/JndiLookup.class')
                    if ($null -eq $jndiClass)
                    {
                        Write-Verbose -Verbose 'jndi class removed successfully'
                        $jarPatched = $true
                    }
                }
                elseif (($null -ne $jndiClass) -and !($Repair)) {
                    Write-Warning 'jndi class found and needs repair!'
                    Write-Verbose -Verbose "Found the following [$($affectedJarList.Count)] jar files:"
                    $affectedJarList
                }
                else {
                    Write-Verbose -Verbose 'jndi class not present in archive, no patch required'
                }
                
                Write-Verbose 'Closing zip...'
                $jarZip.Dispose()

                if ($jarPatched)
                {
                    Write-Verbose 'Overwriting old jar with patched jar...'
                    Copy-Item -Path $jarZipPath -Destination $jar.FullName -Force
                    Write-Verbose -Verbose 'Patch complete.'
                }
            }

            Write-Verbose "Removing zip file"
            Remove-Item -Path $jarZipPath -Force
        }

        Write-Verbose "Removing temp folder"
        Remove-Item -Path $tempDir.FullName -Force
    }
}