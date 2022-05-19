--START
-- Parameters
DECLARE @endpoint NVARCHAR(512) = N'myaccount1.blob.core.windows.net'
DECLARE @port NVARCHAR(5) = N'443'

--Script
DECLARE @jobName NVARCHAR(512) = N'TestTCPNetworkConnection', @jobId BINARY(16), @cmd NVARCHAR(MAX)
IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = @jobName)
EXEC msdb.dbo.sp_delete_job @job_name=@jobName, @delete_unused_schedule=1
EXEC msdb.dbo.sp_add_job @job_name=@jobName, @enabled=1, @job_id = @jobId OUTPUT
DECLARE @stepName NVARCHAR(512) = @endpoint + N':' + @port
SET @cmd = (N'tnc ' + @endpoint + N' -port ' + @port +' | select ComputerName, RemoteAddress, TcpTestSucceeded | Format-List')
EXEC msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=@stepName
, @step_id=1, @cmdexec_success_code=0, @subsystem=N'PowerShell', @command=@cmd, @database_name=N'master'

EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
EXEC msdb.dbo.sp_start_job @job_name=@jobName

--Check status every 5 seconds
DECLARE @RunStatus INT 
SET @RunStatus=10
WHILE ( @RunStatus >= 4)
BEGIN
SELECT distinct @RunStatus  = run_status
FROM [msdb].[dbo].[sysjobhistory] JH JOIN [msdb].[dbo].[sysjobs] J ON JH.job_id= J.job_id 
WHERE J.name=@jobName and step_id = 0
WAITFOR DELAY '00:00:05'; 
END

--Get logs once job completes
SELECT [step_name] AS [Endpoint]
,SUBSTRING([message], CHARINDEX('TcpTestSucceeded',[message]), CHARINDEX('Process Exit',[message])-CHARINDEX('TcpTestSucceeded',[message])) as TcpTestResult
,SUBSTRING([message], CHARINDEX('RemoteAddress',[message]), CHARINDEX('TcpTestSucceeded',[message])-CHARINDEX('RemoteAddress',[message])) as RemoteAddressResult
,[run_status] ,[run_duration], [message]
FROM [msdb].[dbo].[sysjobhistory] JH JOIN [msdb].[dbo].[sysjobs] J ON JH.job_id= J.job_id
WHERE J.name=@jobName and step_id <> 0
--END
