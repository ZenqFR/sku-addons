// Installateur Zenq Addons -- hote .exe de ZenqAddons.ps1.
//
// L'executable embarque le script ZenqAddons.ps1 (ressource) et l'execute
// DANS SON PROPRE PROCESSUS avec le moteur PowerShell de Windows (System.
// Management.Automation, present sur tout Windows 10/11) : pas de console,
// pas de powershell.exe lance a cote, pas de politique d'execution a
// contourner. La fenetre WinForms du script tourne sur le thread STA de l'exe.
//
// L'exe gere aussi sa propre mise a jour : il lit "installer.version" et
// "installer.exe" dans le catalogue public, propose de telecharger la nouvelle
// version, se renomme en .old, pose la nouvelle a sa place et se relance.
//
// Compilation (aucun SDK requis) : voir build.ps1 -- csc.exe du .NET Framework
// 4.x, /target:winexe, /resource:ZenqAddons.ps1.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Installateur Zenq Addons")]
[assembly: AssemblyDescription("Installe et met a jour les addons Zenq pour Sku, Sku et les addons tiers (World of Warcraft Classic Anniversary).")]
[assembly: AssemblyCompany("ZenqFR")]
[assembly: AssemblyProduct("Zenq Addons")]
[assembly: AssemblyCopyright("ZenqFR - https://zenqfr.github.io/sku-addons/")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace ZenqAddons
{
    static class Program
    {
        const string Version = "1.0.0";
        const string CatalogUrl = "https://zenqfr.github.io/sku-addons/catalog.json";
        const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 ZenqAddonsInstaller/" + Version;

        static readonly string DataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ZenqAddons");
        static readonly string LogPath = Path.Combine(DataDir, "journal.log");
        static bool French { get { return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr"; } }
        static string T(string fr, string en) { return French ? fr : en; }

        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12; } catch { }
            try { Directory.CreateDirectory(DataDir); } catch { }
            Log("---- ZenqAddonsInstaller.exe " + Version + " start");

            var parsed = ParseArgs(args);
            bool noGui = parsed.ContainsKey("NoGui");
            bool noSelfUpdate = parsed.ContainsKey("NoSelfUpdate");
            CleanOldExe();
            if (!noGui && !noSelfUpdate)
            {
                try { if (SelfUpdate()) return 0; }
                catch (Exception ex) { Log("self-update: " + ex.Message); }
            }

            string script;
            try { script = ReadResource("ZenqAddons.ps1"); }
            catch (Exception ex)
            {
                Fatal(T("Le script interne est introuvable : ", "The embedded script is missing: ") + ex.Message);
                return 1;
            }

            try
            {
                RunScript(script, parsed);
            }
            catch (Exception ex)
            {
                Log("FATAL: " + ex);
                Fatal(ex.Message + "\n\n" + T("Journal : ", "Log: ") + LogPath);
                return 1;
            }
            Log("---- end");
            return 0;
        }

        // ---------------------------------------------------------------- script
        static void RunScript(string script, Dictionary<string, object> parameters)
        {
            var iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            iss.ApartmentState = ApartmentState.STA;
            iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (var runspace = RunspaceFactory.CreateRunspace(iss))
            {
                runspace.Open();
                runspace.SessionStateProxy.SetVariable("ZenqHostExe", Application.ExecutablePath);
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = runspace;
                    ps.AddScript(script);
                    foreach (var kv in parameters) ps.AddParameter(kv.Key, kv.Value);
                    if (!parameters.ContainsKey("NoSelfUpdate")) ps.AddParameter("NoSelfUpdate", true);
                    try
                    {
                        ps.Invoke();
                    }
                    catch (RuntimeException ex)
                    {
                        // "exit" inside the script surfaces here on some builds; a real
                        // error was already shown by the script's own catch block.
                        Log("script ended: " + ex.Message);
                    }
                    foreach (var err in ps.Streams.Error) Log("script error: " + err);
                }
            }
        }

        static Dictionary<string, object> ParseArgs(string[] args)
        {
            var d = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                if (!a.StartsWith("-")) continue;
                string name = a.TrimStart('-');
                if (name.Length == 0) continue;
                string value = null;
                if (i + 1 < args.Length && !args[i + 1].StartsWith("-")) { value = args[i + 1]; i++; }
                if (value == null) d[name] = true;
                else if (name.Equals("Install", StringComparison.OrdinalIgnoreCase)) d[name] = value.Split(',');
                else d[name] = value;
            }
            return d;
        }

        static string ReadResource(string name)
        {
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream(name))
            {
                if (s == null) throw new FileNotFoundException(name);
                using (var r = new StreamReader(s, Encoding.UTF8, true)) return r.ReadToEnd();
            }
        }

        // ----------------------------------------------------------- self-update
        static bool SelfUpdate()
        {
            string catalog = Download(CatalogUrl + "?t=" + DateTimeOffset.UtcNow.ToUnixTimeSeconds(), 8000);
            if (catalog == null) return false;
            var block = Regex.Match(catalog, "\"installer\"\\s*:\\s*\\{(.*?)\\}", RegexOptions.Singleline);
            if (!block.Success) return false;
            var v = Regex.Match(block.Groups[1].Value, "\"version\"\\s*:\\s*\"([^\"]+)\"");
            var u = Regex.Match(block.Groups[1].Value, "\"exe\"\\s*:\\s*\"([^\"]+)\"");
            if (!v.Success || !u.Success) return false;
            Version remote, local;
            if (!System.Version.TryParse(v.Groups[1].Value, out remote) || !System.Version.TryParse(Version, out local)) return false;
            if (remote <= local) return false;

            var answer = MessageBox.Show(
                string.Format(T("Une nouvelle version de l'installateur ({0}) est disponible (tu as la {1}). La télécharger et relancer maintenant ?",
                                "A newer installer ({0}) is available (you have {1}). Download it and restart now?"), remote, local),
                T("Mise à jour de l'installateur", "Installer update"), MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return false;

            string exe = Application.ExecutablePath;
            string fresh = exe + ".new";
            string old = exe + ".old";
            using (var wc = new WebClient())
            {
                wc.Headers[HttpRequestHeader.UserAgent] = UserAgent;
                wc.DownloadFile(u.Groups[1].Value, fresh);
            }
            var fi = new FileInfo(fresh);
            byte[] head = new byte[2];
            using (var fs = fi.OpenRead()) fs.Read(head, 0, 2);
            if (fi.Length < 10 * 1024 || head[0] != (byte)'M' || head[1] != (byte)'Z')
            {
                File.Delete(fresh);
                MessageBox.Show(T("Le fichier téléchargé n'est pas un programme valide ; mise à jour annulée.", "The downloaded file is not a valid program; update cancelled."), T("Mise à jour", "Update"));
                return false;
            }
            if (File.Exists(old)) File.Delete(old);
            File.Move(exe, old);
            File.Move(fresh, exe);
            Log("self-update: " + local + " -> " + remote);
            Process.Start(new ProcessStartInfo(exe, "-NoSelfUpdate") { UseShellExecute = true });
            return true;
        }

        static void CleanOldExe()
        {
            try { string old = Application.ExecutablePath + ".old"; if (File.Exists(old)) File.Delete(old); } catch { }
        }

        static string Download(string url, int timeoutMs)
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.UserAgent = UserAgent;
                req.Timeout = timeoutMs;
                req.ReadWriteTimeout = timeoutMs;
                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    return r.ReadToEnd();
            }
            catch (Exception ex) { Log("download " + url + ": " + ex.Message); return null; }
        }

        // ------------------------------------------------------------------ misc
        static void Log(string text)
        {
            try { File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  [exe] " + text + Environment.NewLine, Encoding.UTF8); } catch { }
        }

        static void Fatal(string text)
        {
            MessageBox.Show(text, T("Installateur Zenq Addons", "Zenq Addons Installer"), MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
