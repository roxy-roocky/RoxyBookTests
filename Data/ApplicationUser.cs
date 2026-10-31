using Microsoft.AspNetCore.Identity;

namespace RoxyBookTests.Data;

// Add profile data for application users by adding properties to the ApplicationUser class
public class ApplicationUser : IdentityUser
{
    public enum Role
    {
        ADMIN,
        MOA,
        MOE
    }
}

