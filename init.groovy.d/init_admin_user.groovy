#!groovy
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstanceOrNull()

// Skip the setup wizard
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Check if security is already configured
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
if (instance.securityRealm == null || !(instance.securityRealm instanceof HudsonPrivateSecurityRealm)) {
    println "--> Configuring Jenkins Security Realm"
    hudsonRealm.createAccount("admin", "admin123")  // username: admin, password: admin123
    instance.setSecurityRealm(hudsonRealm)
}

// Authorization Strategy: Full access once logged in
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
instance.setAuthorizationStrategy(strategy)

instance.save()
println "--> Jenkins Setup Wizard Skipped. Admin User: admin"
