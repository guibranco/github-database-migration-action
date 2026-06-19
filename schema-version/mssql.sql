IF EXISTS (SELECT * FROM sys.tables WHERE name = 'schema_version')
    DROP TABLE schema_version;
GO

CREATE TABLE schema_version (
    Sequence INT IDENTITY(1,1) PRIMARY KEY,
    Filename NVARCHAR(255) NOT NULL,
    Checksum CHAR(64)      NOT NULL,
    Date     DATETIME      NOT NULL DEFAULT GETDATE(),
    CONSTRAINT UQ_sv_Filename UNIQUE (Filename),
    CONSTRAINT UQ_sv_Checksum UNIQUE (Checksum)
);
GO
