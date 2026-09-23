using System.Collections.Generic;
using output.Repositories.Databases;
using output.StandardData;

namespace output.Domain.Dog
{
    public class DogLogicService
    {
        private readonly IStandardDataRepository<IDogStandardData> _repository;

        public DogLogicService(IStandardDataRepository<IDogStandardData> repository)
        {
            _repository = repository;
        }

        public DogResult Execute()
        {
            // Business logic
            return new DogResult();
        }
    }
}
