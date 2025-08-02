import jenkins.model.Jenkins
import org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl
import hudson.model.User
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def inst = Jenkins.get()

/* --------------------------------------------------------------------
 * 1) Ensure we’re on HudsonPrivateSecurityRealm and that the admin user
 *    exists (creating it only if missing).
 * ------------------------------------------------------------------ */

if (!(inst.securityRealm instanceof HudsonPrivateSecurityRealm)) {
    inst.securityRealm = new HudsonPrivateSecurityRealm(false)
}
def realm = (HudsonPrivateSecurityRealm) inst.securityRealm

// `false` = “don’t auto-create”; returns null if the user is absent
def admin = User.get('admin', /*create*/ false)
if (admin == null) {
    admin = realm.createAccount('admin', 'changeme')   // or read from ENV
    println "--> Created admin user"
}

/* --------------------------------------------------------------------
 * 2) Optionally grant full control to any authenticated user.
 * ------------------------------------------------------------------ */
inst.authorizationStrategy = new FullControlOnceLoggedInAuthorizationStrategy()

/* --------------------------------------------------------------------
 * 3) Inject the SSH public key from the mounted file.
 * ------------------------------------------------------------------ */
def keyPath = System.getenv('ADMIN_SSH_KEY_PATH') ?: '/run/secrets/jenkins_admin_ssh_key.pub'
def keyFile = new File(keyPath)

if (!keyFile.exists() || !keyFile.canRead()) {
    println "WARNING: SSH public key not found at ${keyPath}; skipping injection"
} else {
    def pubKey = keyFile.text.trim()
    // remove previous SSH props to avoid duplicates on restart
    admin.getAllProperties()
         .findAll { it instanceof UserPropertyImpl }
         .each { admin.removeProperty(it) }

    admin.addProperty(new UserPropertyImpl(pubKey))
    admin.save()
    println ">>> Injected SSH public key for 'admin' from ${keyPath}"
}

/* --------------------------------------------------------------------
 * 4) Enable SSHD if it isn’t already.
 * ------------------------------------------------------------------ */
def sshd = inst.getDescriptor('org.jenkinsci.main.modules.sshd.SSHD')
if (!sshd.isEnabled()) {
    sshd.port = Integer.getInteger('SSH_PORT', 2222)
    sshd.save()
    println ">>> SSHD enabled on port ${sshd.port}"
}
