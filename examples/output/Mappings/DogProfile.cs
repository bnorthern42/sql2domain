using AutoMapper;
using output.Models;
using output.StandardData;

namespace output.Mappings
{
    public class DogProfile : Profile
    {
        public DogProfile()
        {
            CreateMap<Dog, DogStandardData>();
        }
    } 
}
