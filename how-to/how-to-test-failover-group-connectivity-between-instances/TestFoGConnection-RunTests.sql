--START
-- Parameters section
DECLARE @node NVARCHAR(512) = N''
DECLARE @port NVARCHAR(512) = N''
DECLARE @serverName NVARCHAR(512) = N''

--Script section
IF EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'TestFoGConnection')
EXEC msdb.dbo.sp_delete_job @job_name = N'TestFoGConnection', @delete_unused_schedule=1

DECLARE @jobId BINARY(16), @cmd NVARCHAR(MAX)

EXEC  msdb.dbo.sp_add_job @job_name=N'TestFoGConnection', @enabled=1, @job_id = @jobId OUTPUT

SET @cmd = (N'tnc ' + @serverName + N' -port 5022 | select ComputerName, RemoteAddress, TcpTestSucceeded | Format-List')
EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Test Port 5022'
, @step_id = 1, @cmdexec_success_code = 0, @on_success_action = 3, @on_fail_action = 3
, @subsystem = N'PowerShell', @command = @cmd, @database_name = N'master'

SET @cmd = (N'tnc ' + @node + N' -port ' + @port +' | select ComputerName, RemoteAddress, TcpTestSucceeded | Format-List')
EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Test HADR Port'
, @step_id = 2, @cmdexec_success_code = 0, @subsystem = N'PowerShell', @command = @cmd, @database_name = N'master'

EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
GO
EXEC msdb.dbo.sp_start_job @job_name = N'TestFoGConnection'
GO
--Check status every 5 seconds
DECLARE @RunStatus INT 
SET @RunStatus=10
WHILE ( @RunStatus >= 4)
BEGIN
SELECT distinct @RunStatus = run_status
FROM [msdb].[dbo].[sysjobhistory] JH JOIN [msdb].[dbo].[sysjobs] J ON JH.job_id = J.job_id 
WHERE J.name=N'TestFoGConnection' and step_id = 0
WAITFOR DELAY '00:00:05'; 
END

--Get logs once job completes
SELECT [step_name]
,SUBSTRING([message], CHARINDEX('TcpTestSucceeded',[message]), CHARINDEX('Process Exit', [message])-CHARINDEX('TcpTestSucceeded',[message])) as TcpTestResult
,SUBSTRING([message], CHARINDEX('RemoteAddress',[message]), CHARINDEX ('TcpTestSucceeded',[message])-CHARINDEX('RemoteAddress',[message])) as RemoteAddressResult
,[run_status] ,[run_duration], [message]
FROM [msdb].[dbo].[sysjobhistory] JH JOIN [msdb].[dbo].[sysjobs] J ON JH.job_id= J.job_id
WHERE J.name = N'TestFoGConnection' and step_id <> 0
--END