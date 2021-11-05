////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) Microsoft Corporation.
//
// @File: Program.cs
//
// @Owner: Dejan Dundjerski
//
// Purpose:
// SQL MI Toolkit for customers to debug various customer side issues.
//
// Notes:
//
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

namespace DllConvertToStream
{
    /// <summary>
    /// Convert DLL to stream and generate SQL statements.
    /// </summary>
    class DllConvertToStream
    {
        private static string Template = @"
USE [master]
GRANT UNSAFE ASSEMBLY TO [<your_user>]

USE [<your_database>]

EXEC sp_configure 'clr strict security', 0
RECONFIGURE

DECLARE @bytes VARBINARY(8000) = HASHBYTES('SHA2_512', {0});
EXEC sp_add_trusted_assembly @bytes,
N'SqlManagedInstanceToolkit, version=0.0.0.0, culture=neutral, publickeytoken=null, processorarchitecture=msil';

--DROP ASSEMBLY [SqlManagedInstanceToolkit]
CREATE ASSEMBLY [SqlManagedInstanceToolkit]
FROM {0} WITH PERMISSION_SET = EXTERNAL_ACCESS;

--DROP PROCEDURE dbo.SqlManagedInstanceToolkit_CheckStorageAccountAccessibility
CREATE PROCEDURE dbo.SqlManagedInstanceToolkit_CheckStorageAccountAccessibility (@strg AS NVARCHAR(MAX), @sas AS NVARCHAR(MAX), @write BIT) AS EXTERNAL NAME [SqlManagedInstanceToolkit].[SqlManagedInstanceToolkit].[CheckStorageAccountAccessibility];

DECLARE @strgToTest NVARCHAR(MAX) = '<your strg>'
DECLARE @sasToTest NVARCHAR(MAX) = '<your sas>'
DECLARE @writeToNewFile BIT = 1
EXEC dbo.SqlManagedInstanceToolkit_CheckStorageAccountAccessibility @strgToTest, @sasToTest, @writeToNewFile
";

        /// <summary>
        /// Convert dll to hex
        /// </summary>
        /// <param name="assemblyPath"></param>
        /// <returns></returns>
        private static string GetHexString(string assemblyPath)
        {
            StringBuilder builder = new StringBuilder("0x");

            using (FileStream stream = new FileStream(assemblyPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                int currentByte = stream.ReadByte();
                while (currentByte > -1)
                {
                    builder.Append(currentByte.ToString("X2", System.Globalization.CultureInfo.InvariantCulture));
                    currentByte = stream.ReadByte();
                }
            }

            return builder.ToString();
        }

        /// <summary>
        /// Generate SQL stmts from template.
        /// </summary>
        /// <returns></returns>
        private static string GenerateFromTemplate()
        {
            var parentPath = Directory.GetParent(Environment.CurrentDirectory);
            string rootPath = parentPath.Parent.Parent.FullName;
            var hexString = GetHexString(string.Format(@"{0}\\Toolkit\\bin\\debug\\Toolkit.dll", rootPath));

            return string.Format(Template, hexString);
        }

        public static void Main()
        {
            File.WriteAllText("commands.sql", GenerateFromTemplate());
        }
    }
}
