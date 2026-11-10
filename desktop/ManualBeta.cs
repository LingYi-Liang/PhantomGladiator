#if !NEXUS
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace PhantomGladiator
{
    sealed class BetaOffer
    {
        public readonly string Id=Guid.NewGuid().ToString("N");
        public string Version, Build, Note, Sha256, Url;
        public long Size, Expires;

        public Dictionary<string, object> Describe()
        {
            return new Dictionary<string, object> {
                { "id", Id }, { "version", Version }, { "build", Build }, { "size", Size }, { "note", Note }
            };
        }
    }

    // Both the installation-bound pass and the offer are signed by the publisher.
    sealed class ManualBeta
    {
        const int MaxEnvelope=16384;
        const string PublicKey="<RSAKeyValue><Modulus>zMgRJ9rAj5xci6ntKp4j33bI9q+xgUUGLSgRTZaJm49EpCC0WqtVZn4RJwFppfD1TYN6nVK48+eaw2glDdHCx267Gxv5LRN4RqEbUgWB65g4yhjhSEnPverIniiN17f4qAHMV5fKgOLKQzSYpSNfqpU3HWLzcVHQbpLxQP5M4o4kj4kfwCW1SqO4grwPNjVzs+rVMzTYUip4y7MVJEQO3Pq+Wzfg32gAh0EvTzL5qIlt3M1KamGXHdPd9k8Uefxti+Uc3BpO48fvLe/R8QP04oPYk4oM1XJaesBOwgZEFdqQ/eOrRLzJv8UZGE6CsoXNkuHkAJg2w81dASqOthTYrQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>";
        readonly string publisher;
        readonly Func<Uri, string> fetch;

        public ManualBeta() : this(PublicKey, ReadOffer) { }
        internal ManualBeta(string publisher, Func<Uri, string> fetch)
        {
            this.publisher=publisher;
            this.fetch=fetch;
        }

        public static string InstallationId()
        {
            var path=Paths.In("beta-installation.txt");
            Directory.CreateDirectory(Paths.Data);
            if (!File.Exists(path))
            {
                try
                {
                    using (var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None))
                    using (var writer=new StreamWriter(file,new UTF8Encoding(false)))
                        writer.Write(Guid.NewGuid().ToString("N"));
                }
                catch (IOException) { if (!File.Exists(path)) throw; }
            }
            Guid id;
            if (!Guid.TryParseExact(File.ReadAllText(path).Trim(),"N",out id))
                throw new HostError("betaIdentity","本机内测编号无法读取。");
            return id.ToString("N");
        }

        static string Text(Dictionary<string, object> fields, string name)
        {
            object value;
            return fields.TryGetValue(name,out value) ? value as string ?? "" : "";
        }

        static long Integer(Dictionary<string, object> fields, string name)
        {
            object value;
            long parsed;
            return fields.TryGetValue(name,out value) &&
                long.TryParse(Convert.ToString(value,CultureInfo.InvariantCulture),NumberStyles.None,CultureInfo.InvariantCulture,out parsed)
                ? parsed : 0;
        }

        static Uri Https(string url)
        {
            Uri address;
            if (url.Length>2048 || !Uri.TryCreate(url,UriKind.Absolute,out address) || address.Scheme!=Uri.UriSchemeHttps ||
                address.Host.Length==0 || address.UserInfo.Length!=0 || address.Fragment.Length!=0) return null;
            return address;
        }

        Dictionary<string, object> Verify(string envelope, string kind, string code)
        {
            if (string.IsNullOrWhiteSpace(envelope) || envelope.Length>MaxEnvelope)
                throw new HostError(code,"内测签名内容为空或过长。");
            try
            {
                var fields=envelope.Trim().Split('.');
                if (fields.Length!=2) throw new FormatException();
                var payload=Convert.FromBase64String(fields[0]);
                var signature=Convert.FromBase64String(fields[1]);
                using (var key=new RSACryptoServiceProvider())
                {
                    key.PersistKeyInCsp=false;
                    key.FromXmlString(publisher);
                    if (!key.VerifyData(payload,CryptoConfig.MapNameToOID("SHA256"),signature))
                        throw new FormatException();
                }
                var serializer=new JavaScriptSerializer { MaxJsonLength=MaxEnvelope,RecursionLimit=8 };
                var data=serializer.Deserialize<Dictionary<string, object>>(new UTF8Encoding(false,true).GetString(payload));
                if (data==null || Text(data,"kind")!=kind) throw new FormatException();
                return data;
            }
            catch (Exception error)
            {
                if (!(error is FormatException) && !(error is CryptographicException) &&
                    !(error is ArgumentException) && !(error is InvalidOperationException)) throw;
                throw new HostError(code,"内测签名无效。");
            }
        }

        static string ReadOffer(Uri url)
        {
            try
            {
                var request=(HttpWebRequest)WebRequest.Create(url);
                request.AllowAutoRedirect=false;
                request.Timeout=6000;
                request.ReadWriteTimeout=6000;
                request.UserAgent="PhantomGladiator";
                using (var response=(HttpWebResponse)request.GetResponse())
                using (var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8))
                {
                    if (response.StatusCode!=HttpStatusCode.OK) throw new WebException();
                    var buffer=new char[MaxEnvelope+1];
                    var count=reader.ReadBlock(buffer,0,buffer.Length);
                    if (count>MaxEnvelope) throw new HostError("betaOffer","内测清单过长。");
                    return new string(buffer,0,count);
                }
            }
            catch (WebException) { throw new HostError("betaOffline","暂时无法读取指定的内测清单。"); }
        }

        public BetaOffer Check(string code, string installation, long now)
        {
            var pass=Verify(code,"pg-beta-pass-1","betaInvite");
            var until=Integer(pass,"expires");
            if (Text(pass,"installation")!=installation || now>=until)
                throw new HostError("betaInvite","内测码已过期或不属于本机编号。");
            var feed=Https(Text(pass,"feed"));
            if (feed==null) throw new HostError("betaInvite","内测入口无效。");

            var manifest=Verify(fetch(feed),"pg-beta-offer-1","betaOffer");
            var offer=new BetaOffer {
                Version=Text(manifest,"version"), Build=Text(manifest,"build"), Note=Text(manifest,"note"),
                Sha256=Text(manifest,"sha256").ToLowerInvariant(), Url=Text(manifest,"url"),
                Size=Integer(manifest,"size"), Expires=Math.Min(until,Integer(manifest,"expires"))
            };
            if (now>=offer.Expires) throw new HostError("betaOffer","指定内测版已到期。");
            if (!Regex.IsMatch(offer.Version,@"\A[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}\z") ||
                !Regex.IsMatch(offer.Build,@"\A[A-Za-z0-9._-]{1,100}\z") ||
                !Regex.IsMatch(offer.Sha256,@"\A[0-9a-f]{64}\z") ||
                offer.Size<=0 || offer.Size>256L*1024*1024 || offer.Note.Length>1200 || Https(offer.Url)==null)
                throw new HostError("betaOffer","指定内测版的包信息无效。");
            return offer;
        }
    }
}
#endif
