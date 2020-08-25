load("@bazel_tools//tools/build_defs/repo:utils.bzl", "update_attrs")

_HTTP_FILE_BUILD = """ 
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "file",
    srcs = ["{}"],
)
"""

# Mostly shamelessly stolen from http.bzl from bazel.  The only difference
# being that we look up which list of urls and which sha256 based on the
# architecture.
def _multiarch_http_file(ctx):
    repo_root = ctx.path(".")
    forbidden_files = [ 
        repo_root,
        ctx.path("WORKSPACE"),
        ctx.path("BUILD"),
        ctx.path("BUILD.bazel"),
        ctx.path("file/BUILD"),
        ctx.path("file/BUILD.bazel"),
    ]   

    downloaded_file_path = ctx.attr.downloaded_file_path
    download_path = ctx.path("file/" + downloaded_file_path)
    if download_path in forbidden_files or not str(download_path).startswith(str(repo_root)):
        fail("'%s' cannot be used as downloaded_file_path in multiarch_http_file" % ctx.attr.downloaded_file_path)

    architecture = ctx.execute(["uname", "-m"]).stdout.strip()
    urls = ctx.attr.urls[architecture]
    sha256 = ctx.attr.sha256[architecture]

    download_info = ctx.download(
        urls,
        "file/" + downloaded_file_path,
        sha256,
        ctx.attr.executable,
    )
    ctx.file("WORKSPACE", "workspace(name = \"{name}\")".format(name = ctx.name))
    ctx.file("file/BUILD", _HTTP_FILE_BUILD.format(downloaded_file_path))

    return update_attrs(ctx.attr, _multiarch_http_file_attrs.keys(), {"sha256": download_info.sha256})

_multiarch_http_file_attrs = {
    "executable": attr.bool(
        doc = "If the downloaded file should be made executable.",
    ),
    "downloaded_file_path": attr.string(
        default = "downloaded",
        doc = "Path assigned to the file downloaded",
    ),
    "sha256": attr.string_dict(
        mandatory = True,
        doc = """The expected SHA-256 of the file downloaded.

This is a mapping from architecture to sha256.

This must match the SHA-256 of the file downloaded. _It is a security risk
to omit the SHA-256 as remote files can change._ At best omitting this
field will make your build non-hermetic. It is optional to make development
easier but should be set before shipping.""",
    ),
    "urls": attr.string_list_dict(
        mandatory = True,
        doc = """A list of URLs to a file that will be made available to Bazel.

This is a mapping from architecture to urls.

Each entry in the map must be a file, http or https URL. Redirections are
followed.  Authentication is not supported.""",
    ),
}

multiarch_http_file = repository_rule(
    attrs = _multiarch_http_file_attrs,
    doc =
        """Downloads a file from a URL and makes it available to be used as a file
group per architecture.

Examples:
  Suppose you need to have a debian package for your custom rules. This package
  is available from http://example.com/package_x86_64.deb or
  http://example.com/package_aarch64.deb. Then you can add to your
  WORKSPACE file:

  python
  load("///util.bzl", "multiarch_http_file")

  multiarch_http_file(
      name = "my_deb",
      urls = {
          "x86_64":["http://example.com/package_x86_64.deb"],
          "aarch64":["http://example.com/package_aarch64.deb"],
      },
      sha256 = {
          "x86_64": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "aarch64": "b720c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      },
  )

  Targets would specify `@my_deb//file` as a dependency to depend on this file.
""",
    implementation = _multiarch_http_file,
)