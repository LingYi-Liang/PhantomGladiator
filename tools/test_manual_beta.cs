using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace PhantomGladiator
{
    static class ManualBetaTest
    {
        static void Check(bool ok, string what)
        {
            if (!ok) throw new Exception(what);
            Console.WriteLine("PASS " + what);
        }

        static string Sign(RSACryptoServiceProvider key, Dictionary<string, object> data)
        {
            var payload=Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(data));
            var signature=key.SignData(payload,CryptoConfig.MapNameToOID("SHA256"));
            return Convert.ToBase64String(payload)+"."+Convert.ToBase64String(signature);
        }

        static void Refuses(Action action, string code, string what)
        {
            try { action(); }
            catch (HostError error) { Check(error.Code==code,what); return; }
            throw new Exception(what);
        }

        static int Main(string[] args)
        {
            try
            {
                var installation=ManualBeta.InstallationId();
                Check(installation==ManualBeta.InstallationId(),"installation identity stays local and stable");
                using (var issuer=new RSACryptoServiceProvider(2048))
                {
                    issuer.PersistKeyInCsp=false;
                    const long now=1800000000;
                    var pass=Sign(issuer,new Dictionary<string, object> {
                        { "kind", "pg-beta-pass-1" }, { "installation", installation },
                        { "expires", now+600 }, { "feed", "https://example.test/beta.txt" }
                    });
                    var offerData=new Dictionary<string, object> {
                        { "kind", "pg-beta-offer-1" }, { "version", "0.40.11" }, { "build", "beta-test" },
                        { "expires", now+300 }, { "size", 100 }, { "sha256", new string('a',64) },
                        { "url", "https://example.test/package.zip" }, { "note", "fixture" }
                    };
                    var signed=Sign(issuer,offerData);
                    var reads=0;
                    var beta=new ManualBeta(issuer.ToXmlString(false), uri => { reads++; return signed; });
                    Refuses(() => beta.Check(pass,Guid.NewGuid().ToString("N"),now),"betaInvite","another installation is rejected");
                    Refuses(() => beta.Check(pass,installation,now+600),"betaInvite","expired pass is rejected");
                    Refuses(() => beta.Check("bad.code",installation,now),"betaInvite","malformed pass is rejected");
                    Check(reads==0,"invalid passes do not query the beta feed");
                    Check(beta.Check(pass,installation,now).Version=="0.40.11" && reads==1,"manual check shows the selected signed version");
                    offerData["version"]="0.40.12";
                    signed=Sign(issuer,offerData);
                    Check(beta.Check(pass,installation,now).Version=="0.40.12" && reads==2,"same pass can check a changed publisher offer");
                    signed=signed.Substring(0,signed.IndexOf('.')+1)+Convert.ToBase64String(new byte[256]);
                    Refuses(() => beta.Check(pass,installation,now),"betaOffer","tampered feed cannot supply a package");
                    offerData["url"]="http://example.test/package.zip";
                    signed=Sign(issuer,offerData);
                    Refuses(() => beta.Check(pass,installation,now),"betaOffer","non-HTTPS package links are refused");
                }

                var build=new BuildInfo { AppVersion="0.40.11" };
                var preview=new UpdateClient(build,true);
                var selected=new BetaOffer { Version="0.40.11",Build="fixture-beta",Url=args[0]+"/beta.zip",
                    Sha256=args[1],Size=long.Parse(args[2],CultureInfo.InvariantCulture) };
                preview.UseBetaOffer(selected);
                preview.Download("github",(done,total,speed)=>{});
                preview.Verify();
                var unpack=typeof(UpdateClient).GetMethod("InstallFiles",BindingFlags.Instance|BindingFlags.NonPublic);
                var installed=(string)unpack.Invoke(preview,null);
                Check(Path.GetFileName(installed).StartsWith("PhantomGladiator-beta-0.40.11-") &&
                    Path.GetDirectoryName(installed)==Paths.In("versions") &&
                    File.ReadAllText(Path.Combine(installed,"PhantomGladiator.exe"))=="preview fixture",
                    "beta ZIP of the same app version verifies and installs side by side");
                Check(File.ReadAllText(Path.Combine(Paths.AppDir,"stable-sentinel.txt"))=="keep" &&
                    !File.Exists(Path.Combine(Paths.AppDir,"PhantomGladiator.exe")),
                    "preview does not write into the stable application folder");
                return 0;
            }
            catch (Exception e) { Console.Error.WriteLine(e.GetType().FullName+": "+e.Message); return 1; }
        }
    }
}
