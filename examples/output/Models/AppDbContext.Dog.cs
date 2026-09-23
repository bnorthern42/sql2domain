using Microsoft.EntityFrameworkCore;

namespace output.Models
{
    public partial class AppDbContext
    {
        public DbSet<Dog> Dogs { get; set; }

        partial void OnModelCreatingDog(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Dog>(entity =>
            {
                entity.ToTable("Dogs");
                // Add Fluent API configurations here if necessary
            });
        }
    }
}
