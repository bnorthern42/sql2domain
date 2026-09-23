using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using output.Models;
using output.StandardData;

namespace output.Repositories.Databases
{
    public interface IStandardDataRepository<T> : IReadOnlyCollection<T>
    {
    }

    public class DogStandardDataRepository : IStandardDataRepository<IDogStandardData>
    {
        private readonly AppDbContext _context;
        private readonly IMapper _mapper;

        public DogStandardDataRepository(AppDbContext context, IMapper mapper)
        {
            _context = context;
            _mapper = mapper;
        }

        public IEnumerator<IDogStandardData> GetEnumerator()
        {
            var data = _context.Dogs.ToList();
            var standardData = _mapper.Map<List<DogStandardData>>(data);
            return standardData.Cast<IDogStandardData>().GetEnumerator();
        }

        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();

        public int Count => _context.Dogs.Count();
    }
}
