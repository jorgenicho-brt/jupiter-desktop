load("@bazel_skylib//lib:paths.bzl", "paths")
load("@ros2//:build_defs.bzl", "if_ros2_version")
load("//tools/private:cc_helper.bzl", "compile_cc_generated_code", "get_hdrs", "get_srcs")
load(
    "//tools/private:ros2_providers.bzl",
    #":ros2_providers.bzl",
    "CGeneratorAspectInfo",
    "CppGeneratorAspectInfo",
    "IdlAdapterAspectInfo",
    "PyGeneratorAspectInfo",
    "Ros2InterfaceInfo",
)
load(":ros2_adapter.bzl", "idl_adapter_aspect")
load(":ros2_utils.bzl", _run_generator = "run_generator")

visibility(["public"])

def _ros2_interface_library_impl(ctx):
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        Ros2InterfaceInfo(
            info = struct(
                srcs = ctx.files.srcs,
            ),
            deps = depset(
                direct = [dep[Ros2InterfaceInfo].info for dep in ctx.attr.deps],
                transitive = [
                    dep[Ros2InterfaceInfo].deps
                    for dep in ctx.attr.deps
                ],
            ),
        ),
    ]

ros2_interface_library = rule(
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".action", ".msg", ".srv"],
            mandatory = True,
        ),
        "deps": attr.label_list(providers = [Ros2InterfaceInfo]),
    },
    implementation = _ros2_interface_library_impl,
    provides = [Ros2InterfaceInfo],
)

_INTERFACE_GENERATOR_C_OUTPUT_MAPPING = [
    "%s.h",
    "detail/%s__functions.h",
    "detail/%s__functions.c",
    "detail/%s__struct.h",
    "detail/%s__type_support.h",
]

_INTERFACE_GENERATOR_CPP_OUTPUT_MAPPING = [
    "%s.hpp",
    "detail/%s__builder.hpp",
    "detail/%s__struct.hpp",
    "detail/%s__traits.hpp",
]

_INTERFACE_GENERATOR_PY_OUTPUT_MAPPING = [
    "_%s.py",
    "_%s_s.c",
]

_TYPESUPPORT_GENERATOR_C_OUTPUT_MAPPING = [
    "%s__type_support_c.cpp",
]

_TYPESUPPORT_GENERATOR_CPP_OUTPUT_MAPPING = [
    "%s__type_support.cpp",
]

_TYPESUPPORT_INTROSPECTION_GENERATOR_C_OUTPUT_MAPPING = [
    "detail/%s__rosidl_typesupport_introspection_c.h",
    "detail/%s__type_support.c",
]

_TYPESUPPORT_INTROSPECTION_GENERATOR_CPP_OUTPUT_MAPPING = [
    "detail/%s__rosidl_typesupport_introspection_cpp.hpp",
    "detail/%s__type_support.cpp",
]

_TYPESUPPORT_FASTRTPS_GENERATOR_C_OUTPUT_MAPPING = [
    "detail/%s__rosidl_typesupport_fastrtps_c.h",
    "detail/%s__type_support_c.cpp",
]

_TYPESUPPORT_FASTRTPS_GENERATOR_CPP_OUTPUT_MAPPING = [
    "detail/%s__rosidl_typesupport_fastrtps_cpp.hpp",
    "detail/dds_fastrtps/%s__type_support.cpp",
]

def _c_generator_aspect_impl(target, ctx):
    package_name = target.label.name
    srcs = target[Ros2InterfaceInfo].info.srcs
    adapter = target[IdlAdapterAspectInfo]

    if len(srcs) == 0:
        fail("ROS2 interface library has no files")

    interface_outputs, cc_include_dir = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._interface_generator,
        ctx.attr._interface_templates,
        _INTERFACE_GENERATOR_C_OUTPUT_MAPPING,
        visibility_control_template = ctx.file._interface_visibility_control,
        mnemonic = "Ros2IdlGeneratorC",
        progress_message = "Generating C IDL interfaces for %{label}",
    )

    typesupport_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_generator,
        ctx.attr._typesupport_templates,
        _TYPESUPPORT_GENERATOR_C_OUTPUT_MAPPING,
        visibility_control_template = if_ros2_version(ctx.file._typesupport_visibility_control, None),
        extra_generator_args = [
            "--typesupports=rosidl_typesupport_fastrtps_c",
            "--typesupports=rosidl_typesupport_introspection_c",
            "--typesupports=rosidl_typesupport_c",
        ],
        mnemonic = "Ros2IdlTypeSupportC",
        progress_message = "Generating C type support for %{label}",
    )

    typesupport_introspection_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_introspection_generator,
        ctx.attr._typesupport_introspection_templates,
        _TYPESUPPORT_INTROSPECTION_GENERATOR_C_OUTPUT_MAPPING,
        visibility_control_template = ctx.file._typesupport_introspection_visibility_control,
        mnemonic = "Ros2IdlTypeSupportIntrospectionC",
        progress_message = "Generating C type introspection support for %{label}",
    )

    typesupport_fastrtps_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_fastrtps_generator,
        ctx.attr._typesupport_fastrtps_templates,
        _TYPESUPPORT_FASTRTPS_GENERATOR_C_OUTPUT_MAPPING,
        visibility_control_template = ctx.file._typesupport_fastrtps_visibility_control,
        mnemonic = "Ros2IdlTypeSupportFastRTPSC",
        progress_message = "Generating C FastRTPS type support for %{label}",
    )

    all_outputs = (
        interface_outputs +
        typesupport_outputs +
        typesupport_introspection_outputs +
        typesupport_fastrtps_outputs
    )
    hdrs = get_hdrs(all_outputs)
    srcs = get_srcs(all_outputs)

    cc_info, _ = compile_cc_generated_code(
        ctx,
        name = package_name + "_c",
        aspect_info = CGeneratorAspectInfo,
        srcs = srcs,
        hdrs = hdrs,
        deps = ctx.attr._c_deps,
        cc_include_dir = cc_include_dir,
    )

    return [
        CGeneratorAspectInfo(cc_info = cc_info),
    ]

c_generator_aspect = aspect(
    implementation = _c_generator_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_interface_generator": attr.label(
            default = Label("@ros2//rosidl:rosidl_generator_c_app"),
            executable = True,
            cfg = "exec",
        ),
        "_interface_templates": attr.label(
            default = Label("@ros2//rosidl:rosidl_generator_c_templates"),
        ),
        "_interface_visibility_control": attr.label(
            default = Label("@ros2//rosidl:rosidl_generator_c_visibility_template"),
            allow_single_file = True,
        ),
        "_typesupport_generator": attr.label(
            default = Label("@ros2//rosidl_typesupport:rosidl_typesupport_generator_c_app"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_templates": attr.label(
            default = Label("@ros2//rosidl_typesupport:rosidl_typesupport_generator_c_templates"),
        ),
        # Remove when dropping Foxy
        "_typesupport_visibility_control": attr.label(
            default = Label("@ros2//rosidl_typesupport:rosidl_typesupport_c_visibility_template"),
            allow_single_file = True,
        ),
        "_typesupport_introspection_generator": attr.label(
            default = Label("@ros2//rosidl:rosidl_typesupport_introspection_generator_c"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_introspection_templates": attr.label(
            default = Label("@ros2//rosidl:rosidl_typesupport_introspection_generator_c_templates"),
        ),
        "_typesupport_introspection_visibility_control": attr.label(
            default = Label("@ros2//rosidl:rosidl_typesupport_introspection_c_visibility_template"),
            allow_single_file = True,
        ),
        "_typesupport_fastrtps_generator": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_c_app"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_fastrtps_templates": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_c_templates"),
        ),
        "_typesupport_fastrtps_visibility_control": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_c_visibility_template"),
            allow_single_file = True,
        ),
        "_c_deps": attr.label_list(
            default = [
                Label("@ros2//rmw"),  # needed by service contracts
                Label("@ros2//rosidl:rosidl_runtime_c"),
                Label("@ros2//rosidl:rosidl_typesupport_introspection_c"),
                Label("@ros2//rosidl_typesupport:rosidl_typesupport_c"),
                Label("@ros2//rosidl_typesupport_fastrtps"),
            ],
            providers = [CcInfo],
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    required_providers = [Ros2InterfaceInfo],
    required_aspect_providers = [IdlAdapterAspectInfo],
    provides = [CGeneratorAspectInfo],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _typesupport_solib_name(package_name, lib):
    return "{}/{}__{}".format(package_name, package_name, lib)

def _cpp_generator_aspect_impl(target, ctx):
    package_name = target.label.name
    srcs = target[Ros2InterfaceInfo].info.srcs
    adapter = target[IdlAdapterAspectInfo]

    if len(srcs) == 0:
        fail("ROS2 interface library has no files")

    interface_outputs, cc_include_dir = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._interface_generator,
        ctx.attr._interface_templates,
        _INTERFACE_GENERATOR_CPP_OUTPUT_MAPPING,
        mnemonic = "Ros2IdlGeneratorCpp",
        progress_message = "Generating C++ IDL interfaces for %{label}",
    )

    typesupport_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_generator,
        ctx.attr._typesupport_templates,
        _TYPESUPPORT_GENERATOR_CPP_OUTPUT_MAPPING,
        extra_generator_args = [
            "--typesupports=rosidl_typesupport_fastrtps_cpp",
            "--typesupports=rosidl_typesupport_introspection_cpp",
            "--typesupports=rosidl_typesupport_cpp",
        ],
        mnemonic = "Ros2IdlTypeSupportCpp",
        progress_message = "Generating C++ type support for %{label}",
    )

    typesupport_introspection_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_introspection_generator,
        ctx.attr._typesupport_introspection_templates,
        _TYPESUPPORT_INTROSPECTION_GENERATOR_CPP_OUTPUT_MAPPING,
        mnemonic = "Ros2IdlTypeSupportIntrospectionCpp",
        progress_message = "Generating C++ type introspection support for %{label}",
    )

    typesupport_fastrtps_outputs, _ = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._typesupport_fastrtps_generator,
        ctx.attr._typesupport_fastrtps_templates,
        _TYPESUPPORT_FASTRTPS_GENERATOR_CPP_OUTPUT_MAPPING,
        visibility_control_template = ctx.file._typesupport_fastrtps_visibility_control,
        mnemonic = "Ros2IdlTypeSupportFastRTPSCpp",
        progress_message = "Generating C++ FastRTPS type support for %{label}",
    )

    interface_cc_info, _ = compile_cc_generated_code(
        ctx,
        name = package_name + "_interface_cpp",
        aspect_info = CppGeneratorAspectInfo,
        srcs = get_srcs(interface_outputs),
        hdrs = get_hdrs(interface_outputs),
        deps = ctx.attr._cpp_deps,
        cc_include_dir = cc_include_dir,
    )

    typesupport_introspection_cc_info, _, _, typesupport_introspection_dynamic_library = compile_cc_generated_code(
        ctx,
        name = package_name + "_typesupport_introspection_cpp",
        aspect_info = CppGeneratorAspectInfo,
        srcs = get_srcs(typesupport_introspection_outputs),
        hdrs = get_hdrs(typesupport_introspection_outputs),
        deps = ctx.attr._cpp_deps,
        cc_info_deps = [interface_cc_info],
        cc_include_dir = cc_include_dir,
        use_default_visibility = True,
        dynamic_link_aspect_info = CppGeneratorAspectInfo,
        dynamic_library_name = _typesupport_solib_name(package_name, "rosidl_typesupport_introspection_cpp"),
    )

    typesupport_fastrtps_cc_info, _, _, typesupport_fastrtps_dynamic_library = compile_cc_generated_code(
        ctx,
        name = package_name + "_typesupport_fastrtps_cpp",
        aspect_info = CppGeneratorAspectInfo,
        srcs = get_srcs(typesupport_fastrtps_outputs),
        hdrs = get_hdrs(typesupport_fastrtps_outputs),
        deps = ctx.attr._cpp_deps,
        cc_info_deps = [interface_cc_info],
        cc_include_dir = cc_include_dir,
        use_default_visibility = True,
        dynamic_link_aspect_info = CppGeneratorAspectInfo,
        dynamic_library_name = _typesupport_solib_name(package_name, "rosidl_typesupport_fastrtps_cpp"),
    )

    typesupport_cc_info, _, _, typesupport_dynamic_library = compile_cc_generated_code(
        ctx,
        name = package_name + "_typesupport_cpp",
        aspect_info = CppGeneratorAspectInfo,
        srcs = get_srcs(typesupport_outputs),
        hdrs = get_hdrs(typesupport_outputs),
        deps = ctx.attr._cpp_deps,
        cc_info_deps = [interface_cc_info, typesupport_introspection_cc_info, typesupport_fastrtps_cc_info],
        cc_include_dir = cc_include_dir,
        use_default_visibility = True,
        dynamic_link_aspect_info = CppGeneratorAspectInfo,
        dynamic_library_name = _typesupport_solib_name(package_name, "rosidl_typesupport_cpp"),
    )

    cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = [
            interface_cc_info,
            typesupport_cc_info,
            typesupport_introspection_cc_info,
            typesupport_fastrtps_cc_info,
        ],
    )
    typesupport_dynamic_libraries = [
        typesupport_dynamic_library,
        typesupport_introspection_dynamic_library,
        typesupport_fastrtps_dynamic_library,
    ]
    return [
        CppGeneratorAspectInfo(
            cc_info = cc_info,
            typesupport_sos = typesupport_dynamic_libraries,
        ),
    ]

cpp_generator_aspect = aspect(
    implementation = _cpp_generator_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_interface_generator": attr.label(
            default = Label("@ros2//rosidl:rosidl_generator_cpp_app"),
            executable = True,
            cfg = "exec",
        ),
        "_interface_templates": attr.label(
            default = Label("@ros2//rosidl:rosidl_generator_cpp_templates"),
        ),
        "_typesupport_generator": attr.label(
            default = Label("@ros2//rosidl_typesupport:rosidl_typesupport_generator_cpp_app"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_templates": attr.label(
            default = Label("@ros2//rosidl_typesupport:rosidl_typesupport_generator_cpp_templates"),
        ),
        "_typesupport_introspection_generator": attr.label(
            default = Label("@ros2//rosidl:rosidl_typesupport_introspection_generator_cpp"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_introspection_templates": attr.label(
            default = Label("@ros2//rosidl:rosidl_typesupport_introspection_generator_cpp_templates"),
        ),
        "_typesupport_fastrtps_generator": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_cpp_app"),
            executable = True,
            cfg = "exec",
        ),
        "_typesupport_fastrtps_templates": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_cpp_templates"),
        ),
        "_typesupport_fastrtps_visibility_control": attr.label(
            default = Label("@ros2//rosidl_typesupport_fastrtps:rosidl_typesupport_fastrtps_cpp_visibility_template"),
            allow_single_file = True,
        ),
        "_cpp_deps": attr.label_list(
            default = [
                Label("@ros2//rmw"),  # needed by service contracts
                Label("@ros2//rosidl:rosidl_runtime_cpp"),
                Label("@ros2//rosidl:rosidl_typesupport_introspection_cpp"),
                Label("@ros2//rosidl_typesupport:rosidl_typesupport_cpp"),
                Label("@ros2//rosidl_typesupport_fastrtps"),
            ],
            providers = [CcInfo],
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    required_providers = [Ros2InterfaceInfo],
    required_aspect_providers = [IdlAdapterAspectInfo],
    provides = [CppGeneratorAspectInfo],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _ros2_interface_cc_library_impl(ctx):
    cc_infos_c = [dep[CGeneratorAspectInfo].cc_info for dep in ctx.attr.deps]
    cc_infos_cpp = [dep[CppGeneratorAspectInfo].cc_info for dep in ctx.attr.deps]
    typesupport_sos = []
    for dep in ctx.attr.deps:
        typesupport_sos += dep[CppGeneratorAspectInfo].typesupport_sos
    return [
        cc_common.merge_cc_infos(
            direct_cc_infos = cc_infos_c + cc_infos_cpp,
        ),
        OutputGroupInfo(
            typesupport_sos = depset(typesupport_sos),
        ),
    ]

ros2_interface_cc_library = rule(
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            aspects = [idl_adapter_aspect, c_generator_aspect, cpp_generator_aspect],
            providers = [Ros2InterfaceInfo],
        ),
    },
    implementation = _ros2_interface_cc_library_impl,
)

def _py_generator_aspect_impl(target, ctx):
    package_name = target.label.name
    srcs = target[Ros2InterfaceInfo].info.srcs
    adapter = target[IdlAdapterAspectInfo]

    type_support_impl_name = "rosidl_typesupport_c"
    py_extension_name = "{}_s__{}".format(package_name, type_support_impl_name)
    dynamic_library_name = package_name + "/" + py_extension_name

    extra_generated_outputs = ["_{}_s.ep.{}.c".format(package_name, type_support_impl_name)]
    for ext in ["action", "msg", "srv"]:
        if any([f.extension == ext for f in srcs]):
            extra_generated_outputs.append("{}/__init__.py".format(ext))

    interface_outputs, cc_include_dir = _run_generator(
        ctx,
        srcs,
        package_name,
        adapter,
        ctx.executable._py_interface_generator,
        ctx.attr._py_interface_templates,
        _INTERFACE_GENERATOR_PY_OUTPUT_MAPPING,
        extra_generator_args = [
            "--typesupport-impls=%s" % type_support_impl_name,
        ],
        extra_generated_outputs = extra_generated_outputs,
        mnemonic = "Ros2IdlGeneratorPy",
        progress_message = "Generating Python IDL interfaces for %{label}",
    )

    all_outputs = (
        interface_outputs
    )
    hdrs = get_hdrs(all_outputs)
    srcs = get_srcs(all_outputs)

    cc_info, compilation_outputs, dynamic_library, _ = compile_cc_generated_code(
        ctx,
        name = package_name + "_py",
        aspect_info = CGeneratorAspectInfo,
        srcs = srcs,
        hdrs = hdrs,
        deps = ctx.attr._py_ext_c_deps,
        cc_include_dir = cc_include_dir,
        use_default_visibility = True,
        target = target,
        dynamic_link_aspect_info = PyGeneratorAspectInfo,
        dynamic_library_name = dynamic_library_name,
    )

    relative_path_parts = paths.relativize(cc_include_dir, ctx.bin_dir.path).split("/")
    if relative_path_parts[0] == "external":
        py_import_path = paths.join(*relative_path_parts[1:])
    else:
        py_import_path = paths.join(ctx.workspace_name, *relative_path_parts[0:])

    py_info = PyGeneratorAspectInfo(
        cc_info = cc_common.merge_cc_infos(
            direct_cc_infos = [cc_info] + [
                dep[PyGeneratorAspectInfo].cc_info
                for dep in ctx.rule.attr.deps
            ],
        ),
        direct_sources = depset(direct = [f for f in all_outputs if f.path.endswith(".py")] + [dynamic_library]),
        dynamic_libraries = depset(
            direct = [dynamic_library],
            transitive = [
                dep[PyGeneratorAspectInfo].dynamic_libraries
                for dep in ctx.rule.attr.deps
            ],
        ),
        transitive_sources = depset(
            direct = [f for f in all_outputs if f.path.endswith(".py")],
            transitive = [
                dep[PyGeneratorAspectInfo].transitive_sources
                for dep in ctx.rule.attr.deps
            ],
        ),
        imports = depset(
            direct = [py_import_path],
            transitive = [
                dep[PyGeneratorAspectInfo].imports
                for dep in ctx.rule.attr.deps
            ],
        ),
    )

    return [py_info]

def _merge_py_generator_aspect_infos(py_infos):
    return PyGeneratorAspectInfo(
        dynamic_libraries = depset(
            transitive = [info.dynamic_libraries for info in py_infos],
        ),
        transitive_sources = depset(
            transitive = [info.transitive_sources for info in py_infos],
        ),
        imports = depset(transitive = [info.imports for info in py_infos]),
    )

py_generator_aspect = aspect(
    implementation = _py_generator_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_py_interface_generator": attr.label(
            default = Label("@ros2//rosidl_python:rosidl_generator_py_app"),
            executable = True,
            cfg = "exec",
        ),
        "_py_interface_templates": attr.label(
            default = Label("@ros2//rosidl_python:rosidl_generator_py_templates"),
        ),
        "_py_ext_c_deps": attr.label_list(
            default = [
                Label("@//third_party/python:python_headers"),
                Label("@//third_party/python:numpy_headers"),
            ],
            providers = [CcInfo],
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
    },
    required_providers = [Ros2InterfaceInfo],
    required_aspect_providers = [[IdlAdapterAspectInfo], [CGeneratorAspectInfo]],
    provides = [PyGeneratorAspectInfo],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _ros2_interface_py_library_impl(ctx):
    py_info = _merge_py_generator_aspect_infos([
        dep[PyGeneratorAspectInfo]
        for dep in ctx.attr.deps
    ])

    transitive_sources = depset(
        transitive = [
            py_info.transitive_sources,
            py_info.dynamic_libraries,
        ] + [
            dep[PyInfo].transitive_sources
            for dep in ctx.attr._py_deps
        ],
    )

    return [
        DefaultInfo(
            files = depset(transitive = [
                dep[PyGeneratorAspectInfo].direct_sources
                for dep in ctx.attr.deps
            ]),
            runfiles = ctx.runfiles(transitive_files = transitive_sources).merge_all(
                [
                    dep.data_runfiles
                    for dep in ctx.attr._py_deps
                ],
            ),
        ),
        PyInfo(
            transitive_sources = transitive_sources,
            uses_shared_libraries = True,
            imports = depset(
                transitive = [py_info.imports] + [
                    dep[PyInfo].imports
                    for dep in ctx.attr._py_deps
                ],
            ),
            has_py2_only_sources = any([dep[PyInfo].has_py2_only_sources for dep in ctx.attr._py_deps]),
            has_py3_only_sources = any([dep[PyInfo].has_py3_only_sources for dep in ctx.attr._py_deps]),
        ),
    ]

ros2_interface_py_library = rule(
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            aspects = [idl_adapter_aspect, c_generator_aspect, py_generator_aspect],
            providers = [Ros2InterfaceInfo],
        ),
        "_py_deps": attr.label_list(
            default = [
                Label("//third_party/python:numpy"),
                Label("@ros2//rosidl:rosidl_parser"),
                Label("@ros2//rosidl_python:rosidl_generator_py_lib"),
            ],
            providers = [PyInfo],
        ),
    },
    implementation = _ros2_interface_py_library_impl,
)

def _ros2_interface_idl_library_impl(ctx):
    direct_idls = []
    for dep in ctx.attr.deps:
        direct_idls.extend(dep[IdlAdapterAspectInfo].idl_files)

    idl_files = depset(
        direct = direct_idls,
    )

    return [
        DefaultInfo(
            files = idl_files,
        ),
    ]

ros2_interface_idl_library = rule(
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            aspects = [idl_adapter_aspect],
            providers = [Ros2InterfaceInfo],
        ),
    },
    implementation = _ros2_interface_idl_library_impl,
)
