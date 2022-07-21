Function ConvertFrom-MySQLiteDB {
    [cmdletbinding(DefaultParameterSetName = "table")]
    [alias('ConvertFrom-DB')]
    [outputtype("Object")]
    Param(
        [Parameter(
            Position = 0,
            Mandatory,
            HelpMessage = "Enter the path to the SQLite database file.",
            ValueFromPipelineByPropertyName
            )]
        [ValidateNotNullOrEmpty()]
        [alias("database", "fullname")]
        [string]$Path,
        [Parameter(
            Mandatory,
            HelpMessage = "Enter the name of the table with data to import"
            )]
        [ValidateNotNullOrEmpty()]
        [string]$TableName,
        [Parameter(
            Mandatory,
            HelpMessage = "Enter the name of the property map table",
            ParameterSetName = "table"
            )]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyTable,
        [Parameter(
            Mandatory,
            HelpMessage = "Enter an optional hashtable of property names and types.",
            ParameterSetName = "hash"
            )]
        [hashtable]$PropertyMap,
        [Parameter(
            HelpMessage = "Enter a typename to insert",
            ParameterSetName = "hash"
            )]
        [Parameter(ParameterSetName = "table")]
        [string]$TypeName,
        [Parameter(
            HelpMessage = "Write raw objects to the pipeline.",
            ParameterSetName = "raw"
            )]
        [switch]$RawObject
    )
    Begin {
        Write-Verbose "[$((Get-Date).TimeOfDay)] $($myinvocation.mycommand)"
    } #begin

    Process {
        Write-Verbose "[$((Get-Date).TimeOfDay)] Using path $Path "
        $file = resolvedb -Path $path
        if ($file.exists) {
            $connection = opendb -Path $file.path
        }
        else {
            Throw "Failed to find database file $($file.path)"
        }
        #verify table exists
        Write-Verbose "[$((Get-Date).TimeOfDay)] Verify table $tablename"
        $tables = Get-MySQLiteTable -Connection $connection -KeepAlive
        if ($tables.name -contains $tablename) {
            $query = "Select * from $tablename"
            Write-Verbose "[$((Get-Date).TimeOfDay)] Found $Tablename"
            Try {
                $raw = Invoke-MySQLiteQuery -Connection $connection -Query $query -As object -KeepAlive -ErrorAction stop
            }
            Catch {
                Write-Warning $_.exception.message
                closedb $connection
                Throw $_
                #bail out
                return
            }
            Write-Verbose "[$((Get-Date).TimeOfDay)] Found $($raw.count) items"

            <#
                find a mapping table using this priority list
                1. PropertyMap parameter
                2. A table called PropertyMap_tablename

                if nothing found then write a default custom object
            #>
            switch ($pscmdlet.ParameterSetName) {
                "hash" {
                    Write-Verbose "[$((Get-Date).TimeOfDay)] User specified property map"
                    $map = $PropertyMap
                    If ($TypeName) {
                        $oTypename = $TypeName
                    }
                }
                "table" {
                    Write-Verbose "[$((Get-Date).TimeOfDay)] $PropertyTable"
                    $map = Invoke-MySQLiteQuery -Connection $connection -Query "Select * from $propertytable"-KeepAlive -As Hashtable
                    if ($typename) {
                        $oTypename = $TypeName
                    }
                    elseif ($PropertyTable -match "_") {
                        #get the typename from the property table name
                        $oTypename = $PropertyTable.split("_", 2)[1].replace("_", ".")
                    }

                }
                "raw" {
                    Write-Verbose "[$((Get-Date).TimeOfDay)] Writing raw objects to the pipeline"
                    $raw
                }
            }

            if ($map) {
                foreach ($item in $raw) {
                    $tmpHash = [ordered]@{}
                    if ($oTypename) {
                        Write-Verbose "[$((Get-Date).TimeOfDay)] Adding typename $oTypename"
                        $tmpHash.Add("PSTypename", $oTypename)
                    }
                    foreach ($key in $map.keys) {
                        Write-Verbose "[$((Get-Date).TimeOfDay)] Adding key $key"
                        $name = $key
                        #if value of the raw object is byte[], assume it is an exported clixml file
                        if ($item.$key.gettype().name -eq 'Byte[]') {
                            $v = frombytes $item.$key
                        }
                        else {
                            $v = $item.$key
                        }
                        Write-Verbose "[$((Get-Date).TimeOfDay)] Using type $($map[$key])"
                        $value = $v -as $($($map[$key] -as [type]))
                        $tmpHash.Add($name, $value)
                    } #foreach key
                    New-Object -TypeName PSObject -Property $tmpHash
                } #foreach item
            } #if $map
        } #if table found
        else {
            Write-Warning "Failed to find a table called $Tablename $($file.path)"
        }
    } #process

    End {
        Write-Verbose "[$((Get-Date).TimeOfDay)] Closing database connection"
        closedb -connection $connection
        Write-Verbose "[$((Get-Date).TimeOfDay)] Ending $($myinvocation.mycommand)"
    } #end

}
