{{flutter_js}}
{{flutter_build_config}}

const { appVersion, assetsVersion, rendererVersion } = document.documentElement.dataset;
const assetUrl = (version) =>
  version ? new URL(`_web/${version}/`, document.baseURI).href : undefined;
const rendererUrl = assetUrl(rendererVersion);

_flutter.loader.load({
  config: {
    entrypointBaseUrl: assetUrl(appVersion),
    assetBase: assetUrl(assetsVersion),
    canvasKitBaseUrl: rendererUrl ? `${rendererUrl}canvaskit/` : undefined,
  },
});
