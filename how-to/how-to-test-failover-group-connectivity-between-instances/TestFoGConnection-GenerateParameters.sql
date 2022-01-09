SELECT 'DECLARE @server NVARCHAR(512) = N'''+ value + ''''
FROM sys.dm_hadr_fabric_config_parameters
WHERE parameter_name  = 'DnsRecordName'
UNION
SELECT 'DECLARE @node NVARCHAR(512) = N'''+ NodeName + '.' + Cluster + ''''
FROM 
    (SELECT REPLACE(fr.node_name,'.','') AS NodeName, JoinCol = 1
FROM sys.dm_hadr_fabric_partitions fp
JOIN sys.dm_hadr_fabric_replicas fr ON fp.partition_id = fr.partition_id
JOIN sys.dm_hadr_fabric_nodes fn ON fr.node_name = fn.node_name
WHERE service_name like '%ManagedServer%' and replica_role = 2) t1
LEFT JOIN
    (SELECT value as Cluster, JoinCol = 1
FROM sys.dm_hadr_fabric_config_parameters
WHERE parameter_name  = 'ClusterName') t2
ON (t1.JoinCol = t2.JoinCol)
UNION
SELECT 'DECLARE @port NVARCHAR(512) = N'''+ value + ''''
FROM sys.dm_hadr_fabric_config_parameters
WHERE parameter_name = 'HadrPort';