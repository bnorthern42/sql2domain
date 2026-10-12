const { wrapNamespace, setConfig } = require('../sql2domain');

describe('wrapNamespace', () => {
    const namespaceName = 'TestProject.Models';
    const content = `public class TestEntity
{
    public int Id { get; set; }
}`;

    beforeEach(() => {
        // Reset to default config before each test
        setConfig({ encapsulateNamespace: true, copyright: '' });
    });

    it('should generate block-scoped namespace by default', () => {
        const expected = `namespace TestProject.Models
{
    public class TestEntity
    {
        public int Id { get; set; }
    }
}
`;
        const result = wrapNamespace(namespaceName, content);
        expect(result).toBe(expected);
    });

    it('should generate block-scoped namespace when encapsulateNamespace is true', () => {
        setConfig({ encapsulateNamespace: true });
        const expected = `namespace TestProject.Models
{
    public class TestEntity
    {
        public int Id { get; set; }
    }
}
`;
        const result = wrapNamespace(namespaceName, content);
        expect(result).toBe(expected);
    });

    it('should generate file-scoped namespace when encapsulateNamespace is false', () => {
        setConfig({ encapsulateNamespace: false });
        const expected = `namespace TestProject.Models;\n\n${content}\n`;
        const result = wrapNamespace(namespaceName, content);
        expect(result).toBe(expected);
    });

    it('should handle empty content gracefully (block-scoped)', () => {
        setConfig({ encapsulateNamespace: true });
        const expected = `namespace TestProject.Models\n{\n\n}\n`;
        const result = wrapNamespace(namespaceName, '');
        expect(result).toBe(expected);
    });

    it('should handle empty content gracefully (file-scoped)', () => {
        setConfig({ encapsulateNamespace: false });
        const expected = `namespace TestProject.Models;\n\n\n`;
        const result = wrapNamespace(namespaceName, '');
        expect(result).toBe(expected);
    });

    it('should indent properly including empty lines inside block-scoped', () => {
        const contentWithEmptyLines = `line1\n\nline3`;
        setConfig({ encapsulateNamespace: true });
        const expected = `namespace TestProject.Models
{
    line1

    line3
}
`;
        const result = wrapNamespace(namespaceName, contentWithEmptyLines);
        expect(result).toBe(expected);
    });
});
