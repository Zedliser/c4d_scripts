import os, struct, sys
from colorsys import hsv_to_rgb
from vispy import scene, app
import numpy as np

def read_bin_file(file_name):
    """ Accepts bin file and outputs data to plot """
    if os.path.isfile(file_name):

        header_format_desc = [['Номер версии файла', 'B'],
                                ['Стартовый цвет (ргб)', 'B'],
                                ['Частота опроса координат, Гц', 'B'],
                                ['Частота опроса цветов, Гц', 'B'],
                                ['Идентификатор формата координат', 'B'],
                                ['Идентификатор формата цветов', 'B'],
                                ['Количество точек', 'H'],
                                ['Количество цветов', 'H'],
                                ['Время начала миссии, с', 'f'],
                                ['Время окончания миссии, с', 'f'],
                                ['Широта начальной позиции ' + chr(176) + ' с.ш.', 'f'],
                                ['Долгота начальной позиции ' + chr(176) + ' в.д.', 'f'],
                                ['Высота начальной позиции, м', 'f']]
        points_format_desc = [['x, м', 'f'],
                                ['y, м', 'f'],
                                ['z, м', 'f']]
        colors_format_desc = [['hue ', 'B'],
                            ['saturation ', 'B'],
                            ['brightness', 'B']]
        with open(file_name, 'rb') as file:
            header_format = '<' + "".join([i[1] for i in header_format_desc])
            header_format_size = struct.calcsize(header_format)
            check_bytes = file.read(4)
            if check_bytes != b'\xaa\xbb\xcc\xdd':
                print('Неверный формат файла %s' % file_name)
                return
            data = file.read(header_format_size)
            #header = bytearray(size)
            header = struct.unpack(header_format, data)

            if header[0] != 1:
                print('Вывод метаданных данной версии банарных файлов не поддерживается')
                return
            
            file.read(100 - (header_format_size + 4)) # getting rid of zeros between metadata and points data
            
            start_time = header[8]
            points_num = header[6]
            time = np.empty( (points_num, 1) )
            time[0] = start_time
            points_time_step = 1/header[2]
            for i in range(points_num - 1): # making np array of time points
                time[i+1] = start_time + points_time_step*i
            points_format = '<' + "".join([i[1] for i in points_format_desc])
            points = np.empty( (points_num, 3) )
            points_format_size = struct.calcsize(points_format)
            for i in range(points_num): # making np array of coordinates 
                points[i] = struct.unpack(points_format, file.read(points_format_size))
                #print(start_time + points_time_step*i, points_data_read)
            file.read(21700 - (100 + points_format_size*points_num)) # getting rid of leftover zeroes

            # colors_num = header[7]
            colors_time_step = 1/header[3]
            colors_format = '<' + "".join([i[1] for i in colors_format_desc])
            colors = np.empty( (points_num, 3))
            skip_colors = int(points_time_step / colors_time_step)  - 1
            colors_format_size = struct.calcsize(colors_format)
            counter = 0
            for i in range(points_num): # making np array of colors
                bytes_read = file.read(colors_format_size)
                counter += colors_format_size
                colors[i] = [i/255 for i in struct.unpack(colors_format, bytes_read)]
                for _ in range(skip_colors):
                    file.read(colors_format_size)
                    counter += colors_format_size
                #print(start_time + colors_time_step*i, colors_data_read)
            return [time, points, colors]
    else:
        print('Файл %s не найден' % file_name)
        return 0

def determine_prefix(filename):
    """ try to int char from the end of the filename without extension until you hit not a number char and call everything before that a prefix 
    return an empty string if no prefix was found """
    filename_wo_extension = os.path.splitext(os.path.basename(filename))[0]
    for i in range(len(filename_wo_extension)-1, -1, -1):
        try:
            int(filename_wo_extension[i:])
        except:
            if i == len(filename_wo_extension)-1:
                break
            else:
                return filename_wo_extension[:i+1]
    return ""

def find_bins(folder = os.getcwd()):
    # get files in a directory
    # try find those with number before extension
    # find prefix
    files = os.listdir(folder)
    prefixes = {}
    for f in files:
        prefix = determine_prefix(f)
        if prefix == "":
            continue
        elif prefix in prefixes:
            prefixes[prefix] += 1 # TODO check that u can adjust dict values like that 
        else:
            prefixes[prefix] = 1
    
    return prefixes


def first_bin(folder = os.getcwd()):
    files = os.listdir(folder)
    for f in files:
        prefix = determine_prefix(f)
        if prefix != "":
            return f
    return ""

def setup_plot(filename):
    """ Function setups window to host plot and main controls """
    
    # TODO add binaries prefix
    # TODO add bin folder
    # TODO add drone selector
    # TODO add dot/trajectory selector
    canvas = scene.SceneCanvas(title=filename,keys='interactive',bgcolor=(0.2,0.2,0.2),show='True')
    view = canvas.central_widget.add_view()
    return view, canvas

def render_plot(view, canvas, data):
    """ time as axes, xyz - coordinates and color as marker colors """
    p1 = scene.visuals.Markers()
    p1.set_data(data[1], face_color=data[2])
    view.add(p1)
    view.camera = 'turntable' 
    axis = scene.visuals.XYZAxis(parent=view.scene)
    


def plot_data():
    filename = first_bin()
    data = read_bin_file(filename)
    view, canvas = setup_plot(filename)
    render_plot(view, canvas, data)
    # canvas.show()
    app.run()


if __name__ == "__main__":
    plot_data()
