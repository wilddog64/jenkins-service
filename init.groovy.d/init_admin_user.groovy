#!groovy
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstanceOrNull()

// Skip the setup wizard
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Configure local security realm and create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "20Admin25")   // username: admin, password: 20Admin25
instance.setSecurityRealm(hudsonRealm)

// Grant full control to logged-in users
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
instance.setAuthorizationStrategy(strategy)

instance.save()
println "--> Jenkins setup wizard skipped. Admin user 'admin' created."

