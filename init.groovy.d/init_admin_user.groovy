#!groovy
import jenkins.model.*
import hudson.security.*
import hudson.security.csrf.DefaultCrumbIssuer

// ── 0) SKIP setup wizard ──────────────────────────────────────────────
// Jenkins.instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// ── 1) ENSURE SECURITY REALM & ADMIN USER ────────────────────────────
def instance = Jenkins.getInstance()
def realm = instance.getSecurityRealm()

if (!(realm instanceof HudsonPrivateSecurityRealm)) {
    // switch to the default in-Jenkins user database
    realm = new HudsonPrivateSecurityRealm(false)
    instance.setSecurityRealm(realm)
}

def adminPwd = System.getenv('ADMIN_PASS') ?: 'changeMe!'
def adminUser = realm.getUser('admin') ?: realm.createAccount('admin', adminPwd)
// aminUser.setPassword(adminPwd)
adminUser.save()

// ── 2) CRUMB ISSUER (optional, but often wanted) ───────────────────────
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// ── 3) MATRIX AUTHORIZATION STRATEGY ─────────────────────────────────
def oldAuth = instance.getAuthorizationStrategy()
def acl = (oldAuth instanceof GlobalMatrixAuthorizationStrategy)
          ? oldAuth
          : new GlobalMatrixAuthorizationStrategy()

// 3a) rename ambiguous 'admin' → explicit (and devs if needed)
def mapping = ['admin':'user:admin']
acl.grantedPermissions.each { perm, sidSet ->
    mapping.each { oldSid, newSid ->
        if (sidSet.remove(oldSid)) {
            sidSet.add(newSid)
        }
    }
}

// 3b) strip out any legacy "PermissionId:admin" entries
acl.grantedPermissions.each { perm, sidSet ->
    sidSet.removeAll { it.startsWith("${perm.id}:admin") }
}

// 3c) collapse all admin variants into exactly one 'admin'
acl.grantedPermissions.each { perm, sidSet ->
    if (sidSet.remove('user:admin') || sidSet.remove('admin')) {
        sidSet.add('admin')
    }
}

// 3d) grant Overall/Read + Overall/Administer to the final 'admin' row
// Use the built-in constants so we get the correct Permission objects
[ Jenkins.READ, Jenkins.ADMINISTER ].each { perm ->
    if (!acl.grantedPermissions[perm]?.contains('admin')) {
        acl.add(perm, 'admin')
    }
}

// ── 4) INSTALL AND SAVE ────────────────────────────────────────────────
instance.setAuthorizationStrategy(acl)
instance.save()

println "✔ Security realm, admin user, and matrix authorization configured."
