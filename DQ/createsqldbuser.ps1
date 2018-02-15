Param(
        [string]$osUsername,
        [string]$osPassword,
	[string]$dbUserName,
	[string]$dbPassword,
	[string]$dbmrsuser,
	[string]$dbmrspwd,
	[string]$dbrefdatauser,
	[string]$dbrefdatapwd,
	[string]$dbprofileuser,
	[string]$dbprofilepwd,
	 [string]$dbName
)

Enable-PSRemoting -Force
$credential = New-Object System.Management.Automation.PSCredential @(($env:COMPUTERNAME + "\" + $osUsername), (ConvertTo-SecureString -String $osPassword -AsPlainText -Force))

Invoke-Command -Credential $credential -ComputerName $env:COMPUTERNAME -ArgumentList $dbUsername,$dbPassword,$dbmrsuser,$dbmrspwd,$dbrefdatauser,$dbrefdatapwd,$dbprofileuser,$dbprofilepwd,$dbName -ScriptBlock {
    Param 
    (
        [string]$dbUsername,
        [string]$dbPassword,
		[string]$dbmrsuser,
		[string]$dbmrspwd,
		[string]$dbrefdatauser,
		[string]$dbrefdatapwd,
		[string]$dbprofileuser,
		[string]$dbprofilepwd,
        [string]$dbName
    )

function writeLog {
    Param([string] $log)
    $dateAndTime = Get-Date
    "$dateAndTime : $log" | Out-File -Append C:\Informatica\Archive\scripts\createdbusers.log
}

function waitTillDatabaseIsAlive {
Param([string] $dbName)
    $connectionString = "Data Source=localhost;Integrated Security=true;Initial Catalog=" + $dbName + ";Connect Timeout=3;"
    $sqlConn = new-object ("Data.SqlClient.SqlConnection") $connectionString
    $sqlConn.Open()

    $tryCount = 0
    while($sqlConn.State -ne "Open" -And $tryCount -lt 100) {
        $dateAndTime = Get-Date
        writeLog "Attempt $tryCount"

	    Start-Sleep -s 30
	    $sqlConn.Open()
	    $tryCount++
    }

    if ($sqlConn.State -eq 'Open') {
	    $sqlConn.Close();
	    writeLog "Connection to MSSQL Server succeed"
    } else {
        writeLog "Connection to MSSQL Server failed"
        exit 255
    }
}

function executeSQLStatement {
    Param([String] $sqlStatement,, [string] $dbName)

    $errorFlag = 1
    $tryCount = 0

    $error.clear()

    while($errorFlag -ne 0 -And $tryCount -lt 30) {
        sleep 1
        $tryCount++
        try {
            Invoke-Sqlcmd -ServerInstance '(local)' -Database $dbName -Query $sqlStatement
            $errorFlag = $error.Count
        } catch {
            $errorFlag = $error.Count
        } finally {
			if($errorFlag -ne 0) {
				writeLog "Error: $error"
				$error.clear()
			}
		}
    }

    if($errorFlag -eq 1 -And $tryCount -eq 3) {
        writeLog "User creation failed"
		exit 255
    } else {
		writeLog "Statement execution passed"
	}
}


function createDatabase {
		Param([String] $dbName)
		$newDatabase = "CREATE DATABASE " + $dbName + " ON ( NAME = " + $dbName + "_dat, FILENAME = 'C:\SQL_DATA\" + $dbName +".mdf', SIZE = 10MB, MAXSIZE = 1000MB, FILEGROWTH = 5MB ) LOG ON ( NAME = " + $dbName + "_log, FILENAME = 'C:\SQL_DATA\" + $dbName + "log.ldf', SIZE = 5MB, MAXSIZE = 500MB, FILEGROWTH = 5MB )"	

		$databaseSetting = "ALTER DATABASE " + $dbName + " SET READ_COMMITTED_SNAPSHOT ON" 

		writeLog "Creating database: $dbName"
		executeStatement $newDatabase master

		writeLog "Setting database READ_COMMITTED_SNAPSHOT to ON"
		executeStatement $databaseSetting $dbName
	}

	
function createDatabaseUser {
		Param([String] $dbUsername, [String] $dbPassword)

		

			$newLogin = "CREATE LOGIN """ + $dbUsername +  """ WITH PASSWORD = '" + ($dbPassword -replace "'","''") + "'"
			$newUser = "CREATE USER """ + $dbUsername + """ FOR LOGIN """ + $dbUsername + """ WITH DEFAULT_SCHEMA = """ + $dbUsername +""""
			$updateUserRole = "ALTER ROLE db_datareader ADD MEMBER """ + $dbUsername + """;" + 
							"ALTER ROLE db_datawriter ADD MEMBER """ + $dbUsername + """;" + 
							"ALTER ROLE db_ddladmin ADD MEMBER """ + $dbUsername + """"
			$newSchema = "CREATE SCHEMA """ + $dbUsername + """ AUTHORIZATION """ + $dbUsername + """"

			writeLog "Creating db user: $dbUsername" 
			executeStatement $newLogin $dbName
			executeStatement $newUser $dbName
			executeStatement $updateUserRole $dbName
			executeStatement $newSchema $dbName
		
	}

	$error.clear()
netsh advfirewall firewall add rule name="Informatica_PC_MSSQL" dir=in action=allow profile=any localport=1433 protocol=TCP

    mkdir -Path C:\Informatica\Archive\logs 2> $null
    mkdir -Path C:\SQL_DATA


	waitTillDatabaseIsAlive master
	
	createDatabase $dbName
	createDatabaseUser $dbUsername $dbPassword
	createDatabaseUser $dbmrsuser $dbmrspwd
	createDatabaseUser $dbrefdatauser $dbrefdatapwd
	createDatabaseUser $dbprofileuser $dbprofilepwd
