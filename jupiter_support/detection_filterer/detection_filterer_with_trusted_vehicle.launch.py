import os
from pathlib import Path
from os import getenv
import yaml

import launch
from launch.actions import DeclareLaunchArgument, ExecuteProcess
from launch.substitutions import LaunchConfiguration
from launch.actions import GroupAction, SetEnvironmentVariable
from launch_ros.actions import Node

CURRENT_PATH = Path(os.getcwd())
PACKAGE_PATH = CURRENT_PATH / Path('autonomy/jupiter/robotics/jupiter-desktop/jupiter_support/detection_filterer')
DETECTION_FILTERER_PATH = Path('autonomy/jupiter/robotics/halo/detection_filterer')

# getenv returns None if not set
PROGRAM = getenv("PROGRAM", "jupiter")
SYSTEM = getenv("SYSTEM") if getenv("SYSTEM") else "bedrock"
MACHINE_ID = getenv("MACHINE_ID")
VPU_POSITION = getenv("VPU_POSITION")
VEHICLE = getenv("VEHICLE")
IMPLEMENT = getenv("IMPLEMENT")
INORBIT = getenv("INORBIT")
MACHINE_NAME = getenv(
    "SYSTEM_UNIQUE_ID", f"{SYSTEM}_{MACHINE_ID}"
)  # Default to old structure if not set

VPU_NAME = f"{MACHINE_NAME}_{VPU_POSITION}"

def load_yaml_config(yaml_path: str, system_key: str):
    print(str(CURRENT_PATH))
    print(yaml_path)
    try:
        config = {}
        with open(yaml_path, "r") as f:
            config = yaml.load(f, Loader=yaml.FullLoader)
        return config[system_key]
    except Exception as e:
        print(e)
        return {}

platform_configs = load_yaml_config(
    yaml_path= str(CURRENT_PATH / Path('autonomy/jupiter/robotics/JupiterEmbedded/src/frame_transform_provider/config/platform_configs.yaml')),
    system_key=SYSTEM)

def create_trusted_vehicle_parameters(vehicle_name: str, extension_distances: [1.0, 1.0, 1.0, 1.0]):
    return {
        'frame_id' : f'{vehicle_name}_footprint',
        'footprint_frame_ids' : {
            'front_left' : f'{vehicle_name}_footprint_front_left_corner',
            'front_right' : f'{vehicle_name}_footprint_front_right_corner',
            'rear_left' : f'{vehicle_name}_footprint_rear_left_corner',
            'rear_right' : f'{vehicle_name}_footprint_rear_right_corner'
        },
        'extension_distances' :{
            'forward' : extension_distances[0],
            'backward' : extension_distances[1],
            'left' : extension_distances[2],
            'right' : extension_distances[3]
        },
    }


detection_filterer_parameters = {
    "trusted_vehicles" : ['combine01', 'combine02'],
    'combine01' : create_trusted_vehicle_parameters('combine01', [1.0, 1.0, 1.0, 1.0]),
    'combine02' : create_trusted_vehicle_parameters('combine02', [1.0, 1.0, 1.0, 1.0]),
    "camera_names": [
        'mockup_camera1', # Uncomment this to get implement detections, currently detection filterer does not seem to handle multiple topics
        'mockup_camera2',
        'mockup_camera3',
        #'mockup_camera3'
        #"T01_T03",
        # "T02_T03",
        # "T02_T04",
        # "T05_T07",
        # "T06_T07",
        # "T06_T08",
        # "T09_T11",
        # "T10_T11",
        # "T10_T12",
        # "T13_T15",
        # "T14_T15",
        # "T14_T16",
    ],
    # TODO(rondomingo): Pull all footprint names from the platform config
    "implement_footprint_front_left_corner_frame_id": "implement_footprint_front_left_corner",
    "implement_footprint_front_right_corner_frame_id": "implement_footprint_front_right_corner",
    "implement_footprint_rear_right_corner_frame_id": "implement_footprint_rear_right_corner",
    "implement_footprint_rear_left_corner_frame_id": "implement_footprint_rear_left_corner",
    "implement_mask_extension_forward_m": 1.0,
    "implement_mask_extension_backward_m": 1.0,
    "implement_mask_extension_left_m": 0.0,
    "implement_mask_extension_right_m": 0.0,
    "implement_frame_id": platform_configs["implement_frame_id"],
    "publish_visualization": True,
    "vehicle_frame_id": platform_configs["vehicle_frame_id"],
}

def launch_detection_generator(vehicle_name: str,
                               detections_out_topic : str,
                               detection_generator_params_dict : dict =
    {'detection_size' : [0.2, 0.2, 0.2],
    'publish_rate': 0.5,
    'msg_queue_size': 4}
                               ):
    launch_entities = []

    # Detection generator node
    node_params_dict = {
        'viz_markers_ns': 'detections',
        'viz_markers_rgba' : [1.0, 1.0, 0.0, 0.5]
    }
    node_params_dict.update(detection_generator_params_dict)
    detection_generator_node = Node(
        executable = str(DETECTION_FILTERER_PATH / Path('synthetic_detection_generator_node')),
        name='{0}_detection_generator_node'.format(vehicle_name),
        output = 'screen',
        remappings = [
            ('detections', detections_out_topic),
            ('cloud_in', '{0}_filtered_cloud'.format(vehicle_name)),
            ('detections_markers', '{0}_detections_markers'.format(vehicle_name))
        ],
        parameters=[
            node_params_dict
        ]
    )
    launch_entities.append(detection_generator_node)
    return GroupAction(
        actions = launch_entities
    )

def launch_cuboid_to_markers_converter(camera_name: str):

    cuboid_to_marker_node = Node(
        executable = str(DETECTION_FILTERER_PATH / Path('cuboid_to_markers_converter')),
        name = '{0}_cuboid_to_markers_converter'.format(camera_name),
        output = 'log',
        parameters = [
            {
                'viz_markers_ns': 'detections',
                'viz_markers_rgba' : [0.0, 1.0, 0.0, 0.5]
            }
        ],
        remappings = [
            ('detections', '{0}/filtered_localized_detections'.format(camera_name)), # input jupiter_detection_msgs::msg::CuboidArray> message
            #('detections', '{0}/filtered_trusted_vehicle_detections'.format(camera_name)),
            ('detections_markers', 'viz/{0}_filtered_trusted_vehicle_detections'.format(camera_name)) # output visualization_msgs::msg::MarkerArray message
        ]
    )
    return cuboid_to_marker_node

def generate_launch_description():

    ld = launch.LaunchDescription(
        [
            DeclareLaunchArgument(name='env_ros_domain_id', default_value = '11'),
            SetEnvironmentVariable(name='ROS_DOMAIN_ID', value=LaunchConfiguration('env_ros_domain_id')),
            Node(
                executable=str(DETECTION_FILTERER_PATH / Path('detection_filterer_with_trusted_vehicle')),
                output="screen",
                name="detection_filterer",
                arguments = '--dds_domain_id 11'.split(),
                parameters=[detection_filterer_parameters],
            ),
            launch_cuboid_to_markers_converter(camera_name='mockup_camera1'),
            launch_cuboid_to_markers_converter(camera_name='mockup_camera2'),
            launch_cuboid_to_markers_converter(camera_name='mockup_camera3'),

            # Grain cart synthetic detections
            launch_detection_generator(vehicle_name='grain_cart',
                                       detections_out_topic='mockup_camera1/localized_detections',
                                       detection_generator_params_dict = {'detection_size' : [0.4, 0.4, 0.4],
                                                                   'publish_rate': 0.3,
                                                                   'msg_queue_size': 4}
                                       ),

            # Combine 01 synthetic detections
            launch_detection_generator(vehicle_name='combine01',
                                       detections_out_topic='mockup_camera2/localized_detections',
                                       detection_generator_params_dict = {'detection_size' : [0.4, 0.4, 0.4],
                                                                          'publish_rate': 0.3,
                                                                          'msg_queue_size': 4}
                                       ),

            # Combine 02 synthetic detections
            launch_detection_generator(vehicle_name='combine02',
                                       detections_out_topic='mockup_camera3/localized_detections',
                                       detection_generator_params_dict = {'detection_size' : [0.4, 0.4, 0.4],
                                                                          'publish_rate': 0.3,
                                                                          'msg_queue_size': 4}
                                       ),
        ]
    )
    return ld