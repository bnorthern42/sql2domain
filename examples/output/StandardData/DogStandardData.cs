namespace output.StandardData
{
    public class DogStandardData : IDogStandardData
    {
        private DogStandardData()
        {
        }

        public int Id { get; private set; }
        public string Name { get; private set; }
        public string Breed { get; private set; }
        public decimal Weight { get; private set; }
        public int Age { get; private set; }
        public bool IsVaccinated { get; private set; }
    }
}
