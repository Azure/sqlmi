-- ***************************************************************************************************************************
-- Azure SQL Managed Instance (aka SQLMI) how-to queries 
-- If you are interested in the whole series with screenshots and explanations, please check out https://aka.ms/sqlmi-howto
-- Shared under MIT licence
-- Copyright @2021 Microsoft
-- ***************************************************************************************************************************


-- ***************************************************************************************************************************
-- Service Tier basic information
-- ***************************************************************************************************************************

-- Determines if we are using SQL MI
IF( SERVERPROPERTY('EngineEdition') = 8 ) 
BEGIN
    PRINT 'This is an Azure SQL Managed Instance.';
END
ELSE
BEGIN
	PRINT 'This is NOT an Azure SQL Managed Instance.';
END

-- Gets the SQLMI Service Tier
SELECT TOP 1 sku as ServiceTier
	FROM [sys].[server_resource_stats]
	ORDER BY end_time DESC;

-- Gets the SQLMI Hardware Generation
SELECT TOP 1 hardware_generation as HardwareGeneration
	FROM [sys].[server_resource_stats]
	ORDER BY end_time DESC;


-- ***************************************************************************************************************************
-- CPU Cores and total amount of RAM
-- ***************************************************************************************************************************

-- Gets the number of CPU vCores and the total amount of RAM
SELECT cpu_rate / 100 as CPU_vCores,
	CAST( (process_memory_limit_mb) /1024. as DECIMAL(9,1)) as TotalMemoryGB
	FROM sys.dm_os_job_object;

-- Displays total & available amounts of RAM
SELECT cpu_rate / 100 as CPU_vCores,
		CAST( (process_memory_limit_mb) /1024. as DECIMAL(9,1)) as TotalMemoryGB,
		CAST( non_sos_mem_gap_mb /1024. as DECIMAL(9,1)) as NonSOSMemGapGB,
		CAST( (process_memory_limit_mb - non_sos_mem_gap_mb) /1024. as DECIMAL(9,1)) as TotalAvailableMemoryGB
	FROM sys.dm_os_job_object;


-- ***************************************************************************************************************************
-- Disk Space 
-- ***************************************************************************************************************************
-- Gets the total Reserved & Used Disk Space
SELECT TOP 1 CAST( reserved_storage_mb / 1024. as DECIMAL(9,2) ) as ReservedStorageGB, 
			CAST( storage_space_used_mb / 1024. as DECIMAL(9,2) ) as UsedStorageGB,  
			CAST( (storage_space_used_mb * 100. / reserved_storage_mb) as DECIMAL(9,2)) as [ReservedStoragePercentage]
       FROM master.sys.server_resource_stats
       ORDER BY end_time DESC;

-- Gets the available space for TempDB
SELECT vs.volume_mount_point as VolumeMountPoint,
		CAST(MIN(total_bytes / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as LocallyUsedGB,
		CAST(MIN(available_bytes / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as LocallyAvailableGB,
		CAST(MIN((total_bytes+available_bytes) / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as LocallyTotalGB
	FROM sys.master_files AS f
		CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) vs
	WHERE UPPER(vs.volume_mount_point) like 'C:\%' 
	GROUP BY vs.volume_mount_point;

-- Gets the total amount of space available on SQLMI 
-- This one can be bigger than the total Reserved disk space on GP (General Purpose) service tier
SELECT SUM(TotalGB) as TotalSpaceGB
	FROM (
	SELECT vs.volume_mount_point as VolumeMountPoint,
		   CAST(MIN(total_bytes / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as UsedGB,
		   CAST(MIN(available_bytes / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as AvailableGB,
		   CAST(MIN((total_bytes+available_bytes) / 1024. / 1024 / 1024) AS NUMERIC(9,2)) as TotalGB
	FROM sys.master_files AS f
		CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.file_id) vs
	GROUP BY vs.volume_mount_point) fsrc;


-- ***************************************************************************************************************************
-- The last SQL MI failover
-- ***************************************************************************************************************************

-- Determines the last SQL MI failover time
select sqlserver_start_time as LastInstanceStart, DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) as HoursSinceFailover
       from sys.dm_os_sys_info;


-- ***************************************************************************************************************************
-- SQL MI Failover Group configuration
-- ***************************************************************************************************************************

-- Determines if your SQL MI is using Failover Group
DECLARE @FGpartnerServer NVARCHAR(32);
SELECT @FGpartnerServer = partner_server
	FROM sys.dm_hadr_fabric_continuous_copy_status;
IF( NOT EXISTS (SELECT 1 as IsPrimaryReplica FROM sys.dm_hadr_database_replica_states rs WHERE rs.is_primary_replica = 1 ) )
BEGIN
	SELECT 'Your have established a connection to a Secondary Replica of SQL MI, where the information about Failover Groups is not available!' as FailoverGroupInfo;
END
ELSE 
BEGIN
	IF( @FGpartnerServer IS NOT NULL )
	BEGIN
		SELECT 'Your SQL MI is using Failover Group with a partner SQL MI ''' + @FGpartnerServer + '.database.windows.net''' as FailoverGroupInfo;
	END
	ELSE
		SELECT 'Your SQL MI is NOT using Failover Groups!' as FailoverGroupInfo;
END

-- ***************************************************************************************************************************
-- SQL MI Failover Group & HA Replicas Details
-- ***************************************************************************************************************************

-- Exposes SQL MI Replicas count
SELECT IsPrimaryReplica, 
		CASE WHEN DATABASEPROPERTYEX ('master', 'Updateability' ) = 'READ_ONLY' THEN 1 ELSE 0 END as IsHAReplica,
		LocallyVisibleHAReplicas,
		CASE WHEN GeoPartnerName IS NOT NULL AND ReplicaRole != 0 THEN 1 ELSE 0 END as IsGeoReplica,
		CASE WHEN GeoPartnerName IS NOT NULL AND ReplicaRole = 0 THEN 1 ELSE CASE WHEN GeoPartnerName IS NULL AND ReplicaRole IS NULL THEN NULL ELSE 0 END END as IsGeoReplicated
	FROM 
	(SELECT MAX( CAST(is_primary_replica AS INT) ) as IsPrimaryReplica,
			MAX( role ) as ReplicaRole,
			MAX( partner_server ) as GeoPartnerName,
			SUM( CASE WHEN is_primary_replica = 0 AND is_commit_participant = 1 THEN 1 ELSE 0 END ) as LocallyVisibleHAReplicas
		FROM sys.dm_hadr_database_replica_states rs
			LEFT JOIN sys.dm_hadr_fabric_continuous_copy_status fgc
				ON rs.group_id = fgc.physical_database_id
		WHERE rs.database_id = (SELECT ISNULL(MAX(maxsrc.database_id),4) FROM sys.dm_hadr_database_replica_states maxsrc WHERE maxsrc.database_id BETWEEN 5 AND 32759)
	) src;


-- ***************************************************************************************************************************
-- SQL MI Failover Group & HA Replicas Details
-- ***************************************************************************************************************************
-- Shows which Databases have Lag and/or Health Problems
SELECT DB_NAME(database_id) as DatabaseName,
		AVG(secondary_lag_seconds*1.0) as AVGSecondaryLagSeconds,
		SUM( CASE WHEN synchronization_health <> 2 THEN 1 ELSE 0 END ) as NonHealthyReplicas,
		SUM( CASE WHEN database_state <> 0 THEN 1 ELSE 0 END ) as NonOnlineReplicas,
		SUM( CASE WHEN is_suspended <> 0 THEN 1 ELSE 0 END ) as SuspendedReplicas
	FROM sys.dm_hadr_database_replica_states
	GROUP BY database_id
	ORDER BY DB_NAME(database_id);

-- Shows which replicas have problems
SELECT CASE WHEN fabric_replica_role_desc IS NOT NULL THEN fabric_replica_role_desc ELSE link_type END as ReplicaRole,
	CASE WHEN replication_endpoint_url IS NOT NULL THEN replication_endpoint_url ELSE partner_server END as EndpointURL, 
	synchronization_state_desc, is_commit_participant, synchronization_health_desc,
	is_suspended, suspend_reason_desc,
	DB_NAME(repl_states.database_id) as DatabaseName, 
	repl_states.database_state_desc
	FROM sys.dm_hadr_database_replica_states repl_states
       LEFT JOIN sys.dm_hadr_fabric_replica_states frs
                     ON repl_states.replica_id = frs.replica_id
              LEFT OUTER JOIN sys.dm_hadr_physical_seeding_stats seedStats
                     ON seedStats.remote_machine_name = replication_endpoint_url
                     AND (seedStats.local_database_name = repl_states.group_id OR seedStats.local_database_name = DB_NAME(database_id))
                     --AND seedStats.internal_state_desc NOT IN ('Success', 'Failed')
              LEFT OUTER JOIN sys.dm_hadr_fabric_continuous_copy_status fccs
                     ON repl_states.group_database_id = fccs.copy_guid
	ORDER BY ReplicaRole DESC, DatabaseName;

-- Measures Lag & last hardened & redone timestamps for HA & DR (Failover Groups) scenarios
SELECT CASE WHEN fabric_replica_role_desc IS NOT NULL THEN fabric_replica_role_desc ELSE link_type END as ReplicaRole,
	CASE WHEN replication_endpoint_url IS NOT NULL THEN replication_endpoint_url ELSE partner_server END as EndpointURL, 
	DB_NAME(repl_states.database_id) as DatabaseName, 
	synchronization_state_desc, 
	synchronization_health_desc,
	secondary_lag_seconds, 
	last_commit_time, 
	last_hardened_time, last_redone_time, DATEDIFF( MS, last_commit_time, last_redone_time) / 1024. as LastRedoDelaySec, 
	log_send_queue_size, redo_queue_size
	FROM sys.dm_hadr_database_replica_states repl_states
		LEFT JOIN sys.dm_hadr_fabric_replica_states frs
            ON repl_states.replica_id = frs.replica_id
		LEFT OUTER JOIN sys.dm_hadr_fabric_continuous_copy_status fccs
            ON repl_states.group_database_id = fccs.copy_guid
	ORDER BY DatabaseName

-- The queries in this section can be enhanced with the following predicate to show only the problematic situations
	--WHERE ( ( synchronization_health <> 2 ) 
	--	     OR 
	--		 ( database_state <> 0 ) 
	--		 OR
	--		 ( synchronization_state <> 2 AND is_commit_participant = 1 )
	--		 OR 
	--		 (is_suspended = 1) )

-- ***************************************************************************************************************************
-- End
-- ***************************************************************************************************************************