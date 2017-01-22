configuration SQLConfiguration {
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String] $SqlInstallationISOUri = 'https://tenantartifacts.blob.azurestack.local/iso/SQLServer2016SP1-FullSlipstream-x64-ENU.iso',
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String] $SQLInstanceName = 'MSSQLSERVER',
        
        [Parameter()]
        [System.String[]] $Features = 'SQLENGINE',
        
        [Parameter(Mandatory)]
        [pscredential] $SetupCredentials,
        
        [Parameter()]
        [ValidateSet('Windows','SQL')]
        [System.String] $SecurityMode = 'SQL',
        
        [Parameter()]
        [System.String] $ProductId = [System.String]::Empty,
        
        [Parameter()]
        [Uint16] $Port = 1433
    )

    $NormalizedFeatures = foreach ($F in $Features) {
        $F.ToUpper().Trim()
    }
    $NormalizedFeatures = $NormalizedFeatures -join ','

    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    Import-DscResource -ModuleName xSQLServer -ModuleVersion 3.0.0.0
    Import-DscResource -ModuleName xNetworking -ModuleVersion 3.0.0.0
    Import-DscResource -ModuleName xDownloadISO -ModuleVersion 1.0
    Import-DscResource -ModuleName xStorage -ModuleVersion 2.8.0.0
    
    Node localhost {
        xDownloadISO DownloadSQL {
            SourcePath = $SqlInstallationISOUri
            DestinationDirectoryPath = 'C:\SQL2016'
        }

        xDisk SqlDataDisk {
            DiskNumber = 1
            FSFormat = 'NTFS'
            DriveLetter = 'G'
            FSLabel = 'SQLData'
        }

        xDisk SqlLogDisk {
            DiskNumber = 2
            FSFormat = 'NTFS'
            DriveLetter = 'I'
            FSLabel = 'SQLLog'
        }

        if ($Features -contains 'SQLENGINE') {
            xSQLServerSetup SQLInstall {
                SourcePath = 'C:'
                SourceFolder = '\SQL2016'
                Features = $NormalizedFeatures
                InstanceName = $SQLInstanceName
                SetupCredential = $SetupCredentials
                SecurityMode = $SecurityMode
                SAPwd = $SetupCredentials
                PID = $ProductId
                SQLSysAdminAccounts = 'Administrators'
                SQLUserDBDir = 'G:\Microsoft SQL Server\Data'
                SQLUserDBLogDir = 'I:\Microsoft SQL Server\Log'
                SQLTempDBDir = 'G:\Microsoft SQL Server\Data'
                SQLTempDBLogDir = 'I:\Microsoft SQL Server\Log'
                SQLBackupDir = 'G:\Microsoft SQL Server\Data'
                DependsOn = '[xDownloadISO]DownloadSQL','[xDisk]SqlDataDisk','[xDisk]SqlLogDisk'
            }
        } else {
            xSQLServerSetup SQLInstall {
                SourcePath = 'C:'
                SourceFolder = '\SQL2016'
                Features = $NormalizedFeatures
                InstanceName = $SQLInstanceName
                SetupCredential = $SetupCredentials
                SecurityMode = $SecurityMode
                SAPwd = $SetupCredentials
                PID = $ProductId
                SQLSysAdminAccounts = 'Administrators'
                DependsOn = '[xDownloadISO]DownloadSQL'
            }
        }

        if ($SecurityMode -eq 'SQL') {
            xSQLServerLogin SQLLogin {
                Ensure = 'Present'
                LoginType = 'SqlLogin'
                SQLInstanceName = $SQLInstanceName
                Name = $SetupCredentials.UserName
                SQLServer = 'localhost'
                LoginCredential = $SetupCredentials
            }
        }

        xSQLServerNetwork SQLTCP {
            InstanceName = $SQLInstanceName
            ProtocolName = 'tcp'
            IsEnabled = $true
            TCPPort = $Port
            RestartService = $true
            DependsOn = '[xSQLServerSetup]SQLInstall'
        }
        
        xFirewall SQLTCP {
            Name = 'SQL TCP Allow Inbound'
            Ensure = 'Present'
            Enabled = 'True'
            Action = 'Allow'
            Direction = 'Inbound'
            Profile = 'Private'
            LocalPort = $Port
            Protocol = 'Tcp'
        }

        xNetConnectionProfile PrivateProfile {
            InterfaceAlias = 'Ethernet'
            NetworkCategory = 'Private'
        }

        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
        }
    }
}