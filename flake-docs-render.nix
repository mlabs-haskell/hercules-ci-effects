{
  perSystem = { config, pkgs, lib, ... }:
  let
    inherit (lib)
      concatMap
      hasPrefix
      removePrefix
      ;

    filterTransformOptions = { sourceName, sourcePath, baseUrl }:
      let sourcePathStr = toString sourcePath;
      in
      opt:
      let
        declarations = concatMap
          (decl:
            if hasPrefix sourcePathStr (toString decl)
            then
              let subpath = removePrefix sourcePathStr (toString decl);
              in [{ url = baseUrl + subpath; name = sourceName + subpath; }]
            else [ ]
          )
          opt.declarations;
      in
      if declarations == [ ]
      then opt // { visible = false; }
      else opt // { inherit declarations; };

  
    renderModule = { sourceName, sourcePath, modules }:
      # TODO: use the render pipeline in flake-parts,
      #       which has support for things like {options}`foo`.
      let
        eval = lib.evalModules {
          modules = [
            {
              options._module.args = lib.mkOption {
                visible = false;
                # type = lib.types.submodule;
              };
            }
            ./effects/effect/effect-module.nix 
          ] ++ modules;
        };
        baseUrl = 
          "https://github.com/hercules-ci/hercules-ci-effects/blob/master" 
            + lib.strings.removePrefix (toString ./.) (toString sourcePath);

      in
      (pkgs.nixosOptionsDoc
        {
          options = eval.options;
          transformOptions = filterTransformOptions {
            inherit sourceName baseUrl sourcePath;
          };
          documentType = "none";
          warningsAreErrors = true;
          markdownByDefault = true;
        }).optionsDocBook;
  in
  {
    packages.generated-option-doc-modularEffect =
      renderModule {
        sourceName = "effect";
        sourcePath = ./effects/effect;
        modules = [ ];
      };

    packages.generated-option-doc-git-auth =
      renderModule {
        sourceName = "git-auth";
        sourcePath = ./effects/modules/git-auth.nix;
        modules = [ ./effects/modules/git-auth.nix ];
      };

    packages.generated-option-doc-git-update =
      renderModule {
        sourceName = "git-auth";
        sourcePath = ./effects/modules/git-update.nix;
        modules = [ ./effects/modules/git-update.nix ];
      };


    packages.generated-antora-files =
      pkgs.runCommand "generated-antora-files"
        {
          nativeBuildInputs = [ pkgs.pandoc pkgs.libxslt.bin ];
          modularEffect = config.packages.generated-option-doc-modularEffect;
          git_auth = config.packages.generated-option-doc-git-auth;
          git_update = config.packages.generated-option-doc-git-update;
        }
        ''
          mkdir -p $out/modules/ROOT/partials/options

          function convert() {
            xsltproc --stringparam title Options \
              -o options.db.xml ${./options.xsl} \
              -
            pandoc --from=docbook --to=asciidoc \
              < options.db.xml\
            | sed -e 's/^ *//'  -e 's/^== *$//'
          }
          convert \
            < $modularEffect \
            >$out/modules/ROOT/partials/options.adoc \

          convert \
            < $git_auth \
            > $out/modules/ROOT/partials/options/git-auth.adoc

           convert\
            < $git_update \
            > $out/modules/ROOT/partials/options/git-update.adoc
        '';
  };
}
