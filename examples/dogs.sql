CREATE TABLE [Dogs] (
    [Id] INT NOT NULL,
    [Name] VARCHAR(50) NOT NULL,
    [Breed] VARCHAR(50) NOT NULL,
    [Weight] DECIMAL(5,2) NOT NULL,
    [Age] INT NOT NULL,
    [IsVaccinated] BIT NOT NULL
);

INSERT INTO [Dogs] ([Id], [Name], [Breed], [Weight], [Age], [IsVaccinated])
VALUES 
    (1, 'Max', 'Golden Retriever', 30.50, 4, 1),
    (2, 'Bella', 'French Bulldog', 11.20, 2, 1),
    (3, 'Charlie', 'German Shepherd', 34.00, 5, 0);
