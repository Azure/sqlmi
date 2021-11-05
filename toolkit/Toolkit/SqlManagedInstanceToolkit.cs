////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Copyright (c) Microsoft Corporation.
//
// @File: SqlManagedInstanceToolkit.cs
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
using System.Text;
using System.Net.NetworkInformation;
using System.IO;
using System.Data.SqlTypes;
using System.Net;
using System.Net.Sockets;
using Microsoft.SqlServer.Server;

/// <summary>
/// SQL MI Toolkit class.
/// </summary>
public partial class SqlManagedInstanceToolkit
{
    /// <summary>
    /// Check storage account accessibility.
    /// </summary>
    /// <param name="storageAccount"></param>
    /// <param name="sasToken"></param>
    /// <param name="executeWriteOperation"></param>
    [Microsoft.SqlServer.Server.SqlProcedure]
    public static void CheckStorageAccountAccessibility(SqlString storageAccount, SqlString sasToken, SqlBoolean executeWriteOperation)
    {
        List<string> result = new List<string>();

        Uri uri = null;
        try
        {
            uri = new Uri(storageAccount.Value);
        }
        catch (UriFormatException)
        {
            result.Add("URI is in the wrong format");
        }

        if (uri != null && uri.Port != 443)
        {
            result.Add("Only https is allowed");
        }

        if (uri != null)
        {
            string hostname = uri.Host;
            string IPAddress = null;

            // Resolve fqdn
            //
            try
            {
                int cnt = 0;
                string addresses = string.Empty;
                IPHostEntry destination = Dns.GetHostEntry(hostname);

                foreach (var addr in destination.AddressList)
                {
                    addresses += addr + ";";

                    if (cnt++ == 0)
                    {
                        IPAddress = addr.ToString();
                    }
                }

                result.Add(string.Format("Hostname {0} was successfully resolved to: {1}.", hostname, addresses));
            }
            catch (SocketException se)
            {
                if (se.ErrorCode == 11001)
                {
                    result.Add(string.Format("Hostname {0} could not be found", hostname));
                }
                else
                {
                    result.Add(string.Format("DNS resolution of {0} thrown following error {1}.", hostname, se.ErrorCode));
                }
            }
            catch (Exception ex)
            {
                result.Add(string.Format("DNS resolution of {0} thrown following exc {1}.", hostname, ex.Message));
            }

            // Check TCP ping
            //
            Ping ping = new Ping();
            try
            {
                PingReply reply = ping.Send(hostname);
                result.Add(string.Format("PING to {0} reported status {1}.", hostname, reply.Status));
            }
            catch (Exception ex)
            {
                result.Add(string.Format("PING to {0} thrown following exc {1}.", hostname, ex.Message));
            }

            // Check tcp connection to 443
            //
            if (IPAddress != null)
            {
                try
                {
                    Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);

                    socket.Connect(IPAddress, 443);

                    if (socket.Connected)
                    {
                        result.Add(string.Format("TCP connect to {0}:443 was successful.", hostname));
                    }
                }
                catch (SocketException se)
                {
                    if (se.ErrorCode == 10061)
                    {
                        result.Add(string.Format("TCP connect to {0}:443 failed because there were no listener. However the port is open.", hostname));
                    }
                    else
                    {
                        result.Add(string.Format("TCP connect to {0}:443 failed with {1}.", hostname, se.Message));
                    }
                }
                catch (Exception ex)
                {
                    result.Add(string.Format("TCP connect to {0}:443 failed with {1}.", hostname, ex.Message));
                }
            }

            if (executeWriteOperation.Value)
            {
                // Try writing to the file
                //
                string requestUri = string.Format("{0}/checktestblob_{1}_{2}?{3}", storageAccount.Value, DateTime.UtcNow.ToString("yyyyMMd_HHmmss"), Guid.NewGuid().ToString("N"), sasToken);
                HttpWebRequest request = HttpWebRequest.CreateHttp(requestUri);
                request.Method = "PUT";
                request.ContentType = "text/plain; charset=UTF-8";
                request.ContentLength = 0;
                request.Headers["x-ms-blob-type"] = "BlockBlob";
                request.Headers["x-ms-version"] = "2020-04-08";
                request.Headers["x-ms-date"] = DateTime.UtcNow.ToString();

                try
                {
                    using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                    {
                        var encoding = string.IsNullOrEmpty(response.CharacterSet) ? Encoding.ASCII : Encoding.GetEncoding(response.CharacterSet);
                        using (StreamReader reader = new StreamReader(response.GetResponseStream(), encoding))
                        {
                            string responseBody = reader != null ? reader.ReadToEnd() : null;

                            result.Add(string.Format("Put request to account {0} returned {1}. Description: {2}; Response: {3};", storageAccount.Value, response.StatusCode, response.StatusDescription, responseBody));
                        }
                    }
                }
                catch (WebException wex)
                {
                    string returnedResponse = string.Empty;
                    HttpWebResponse response = (HttpWebResponse)wex.Response;

                    if (response != null)
                    {
                        var encoding = string.IsNullOrEmpty(response.CharacterSet) ? Encoding.ASCII : Encoding.GetEncoding(response.CharacterSet);

                        using (StreamReader reader = new StreamReader(response.GetResponseStream(), encoding))
                        {
                            returnedResponse = reader != null ? reader.ReadToEnd() : string.Empty;
                        }

                        response.Dispose();
                    }

                    result.Add(string.Format("Put request to account {0} throw an exception {1}. Http response: {2}.", storageAccount.Value, wex.Message, returnedResponse));
                }
            }
        }

        // Expose results.
        //
        foreach (var row in result)
        {
            SqlContext.Pipe.Send(row);
        }
    }
}
