# sqlmi
Azure SQL Managed Instance toolkit

Folders & Projects:
- DllConvertToStream => project that converts Toolkit dll into the stream and crafts the T-SQL statements to load the Toolkit dll into the SQL MI.
- Toolkit => project contains set of .NET CLR store procedures that are useful for debugging and troubleshooting from your SQL MI.
  In case you want to extend with your own store proc, this is the place where you would add your own store proc.
- GeneratedScript => contains already pre-generated scripts that you can use without building above projects.

Generated scripts:
- To install Toolkit use content from commands.sql file and c/p commands to your SQL Managed Instance.
- After executing set of steps you should be able to execute following checks:
	- dbo.SqlManagedInstanceToolkit_CheckStorageAccountAccessibility 
		- Parameters : 
					strgToTest - full uri address of the storage account
					sasToTest - SAS token of storage account
					writeToNewFile - bool flag to enable/disable write check to the storage account?
		- Description : can be used to inspect whether your SQL MI have access to the given storage account and return errors in case storage account is not accessible.
