This repository provides tools and scripts to build and integrate OpenVINO™ AI plugins with Audacity on macOS.  
These plugins enable AI-powered audio effects, generators, and analyzers that run entirely on your local machine, no internet connection required.

NOTE: This project does not include the OpenVINO module itself, its source code can be found at [OpenVINO™ GitHub](https://github.com/intel/openvino-plugins-ai-audacity)

### Features

- **Local AI Processing:** Run AI models locally using OpenVINO™.
- **AI-Powered Audio Tools:** Access advanced audio effects, generators, and analyzers within Audacity.

### Prerequisites

- **Operating System:** macOS 12 or later.
- **Development Tools:** Xcode with Command Line Tools installed.
- **Audacity:** Latest version installed on your system.

### Installation

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/audacity/mod-openvino-macos.git
   cd mod-openvino-macos
   ```

2. **Install Dependencies:**

   Ensure all necessary dependencies are installed. This includes:

   - CMake
   - XCode 16
   - XCode Command Line Tools
   - Brew

3. **Build the Plugins:**

   Execute the build scripts provided in the `scripts` directory:

```sh
    ./scripts/prepare-build.sh
    ./build.sh x86_64 # For Intel based Macs
or 
    ./build.sh arm64 # For Apple silicon based Macs
```

4. **Install the plugin:**

   After building run the installer staging/Audacity-OpenVINO.pkg 

## Troubleshooting

- **Plugin not loading:** Ensure that that your version of Audacity compatible with the plugin.
- **Build errors:** Consult the build logs for specific error messages and ensure that all required development tools are properly configured. You may want to check the CI logs for reference.

## Contributing

Contributions to enhance macOS support for OpenVINO AI plugins in Audacity are welcome.  
Please fork the repository, make your changes, and submit a pull request for review.

## License

This project is licensed under the GNU General Public License v3.0. See the [LICENSE.txt](LICENSE.txt) file for details.
