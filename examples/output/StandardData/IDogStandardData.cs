namespace output.StandardData
{
    public interface IDogStandardData
    {
        int Id { get; }
        string Name { get; }
        string Breed { get; }
        decimal Weight { get; }
        int Age { get; }
        bool IsVaccinated { get; }
    }
}
