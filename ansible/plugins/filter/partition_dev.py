class FilterModule(object):
  def filters(self):
    return {'partition_dev': partition_dev}

def partition_dev(disk, part_no):
  return '/dev/%s%s%s' % (disk['name'], 'p' if disk['name'].startswith('nvme') else '', part_no)
