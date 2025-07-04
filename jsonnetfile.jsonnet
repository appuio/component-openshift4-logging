{
  version: 1,
  dependencies: std.prune([
    {
      source: {
        git: {
          remote: 'https://github.com/projectsyn/jsonnet-libs',
          subdir: '',
        },
      },
      version: 'main',
      name: 'syn',
    },
  ]),
  legacyImports: true,
}
